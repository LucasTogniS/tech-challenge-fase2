#!/usr/bin/env bash
# Remove TODA a infraestrutura da Fase 2 (somente recursos com nomes togglemaster-fase2*
# e a tabela ToggleMasterAnalytics). Não toca em nada da Fase 1.
#
# Ordem importa: o Load Balancer é criado pelo Kubernetes, então ele sai antes do
# cluster; os bancos saem antes dos Security Groups; a VPC sai por último.
. "$(dirname "$0")/lib.sh"

echo "Isto vai APAGAR o cluster EKS, os 3 RDS, o ElastiCache, a fila SQS, a tabela"
echo "DynamoDB, os repositórios ECR e a VPC '$VPC_NAME'. Não há como desfazer."
read -r -p "Digite DESTRUIR para continuar: " resp
[ "$resp" = DESTRUIR ] || { echo "Cancelado."; exit 0; }

existe_cluster() { aws_ eks describe-cluster --name "$CLUSTER" >/dev/null 2>&1; }

# 1. Kubernetes: apagar o Ingress Controller remove o Network Load Balancer
if existe_cluster; then
  log "Kubernetes (Load Balancer do Ingress e aplicações)"
  aws_ eks update-kubeconfig --name "$CLUSTER" --alias "$CLUSTER" >/dev/null
  kubectl delete namespace ingress-nginx togglemaster-auth togglemaster-flag togglemaster-targeting \
    togglemaster-evaluation togglemaster-analytics --ignore-not-found --wait=true --timeout=300s || true
  ok "namespaces removidos (o NLB é apagado junto)"
fi

# 2. Dados
log "RDS"
for db in "${!RDS_DB[@]}"; do
  aws_ rds delete-db-instance --db-instance-identifier "$db" --skip-final-snapshot --delete-automated-backups >/dev/null 2>&1 \
    && ok "$db em remoção" || ok "$db não existe"
done
log "ElastiCache"
aws_ elasticache delete-cache-cluster --cache-cluster-id "$CACHE_ID" >/dev/null 2>&1 \
  && ok "$CACHE_ID em remoção" || ok "$CACHE_ID não existe"
log "SQS e DynamoDB"
if url=$(aws_ sqs get-queue-url --queue-name "$SQS_QUEUE" --query QueueUrl --output text 2>/dev/null); then
  aws_ sqs delete-queue --queue-url "$url" && ok "$SQS_QUEUE removida"
fi
aws_ dynamodb delete-table --table-name "$DDB_TABLE" >/dev/null 2>&1 && ok "$DDB_TABLE removida" || ok "$DDB_TABLE não existe"
log "ECR"
for s in $SERVICES; do
  aws_ ecr delete-repository --repository-name "$ECR_NAMESPACE/$s" --force >/dev/null 2>&1 \
    && ok "$ECR_NAMESPACE/$s removido" || ok "$ECR_NAMESPACE/$s não existe"
done

# 3. EKS
if existe_cluster; then
  log "EKS: node group (3 a 6 min)"
  for ng in $(aws_ eks list-nodegroups --cluster-name "$CLUSTER" --query 'nodegroups[]' --output text); do
    aws_ eks delete-nodegroup --cluster-name "$CLUSTER" --nodegroup-name "$ng" >/dev/null
    aws eks wait nodegroup-deleted --cluster-name "$CLUSTER" --nodegroup-name "$ng" && ok "$ng removido"
  done
  log "EKS: cluster (3 a 6 min)"
  aws_ eks delete-cluster --name "$CLUSTER" >/dev/null
  aws eks wait cluster-deleted --name "$CLUSTER" && ok "$CLUSTER removido"
fi

log "Aguardando RDS e ElastiCache terminarem de sair"
for db in "${!RDS_DB[@]}"; do
  aws rds wait db-instance-deleted --db-instance-identifier "$db" 2>/dev/null || true
done
aws elasticache wait cache-cluster-deleted --cache-cluster-id "$CACHE_ID" 2>/dev/null || true
ok "bancos removidos"

aws_ rds delete-db-subnet-group --db-subnet-group-name "$DB_SUBNET_GROUP" 2>/dev/null && ok "$DB_SUBNET_GROUP removido" || true
aws_ elasticache delete-cache-subnet-group --cache-subnet-group-name "$CACHE_SUBNET_GROUP" 2>/dev/null && ok "$CACHE_SUBNET_GROUP removido" || true

# 4. VPC (e tudo dentro dela)
VPC=$(aws_ ec2 describe-vpcs --filters "Name=tag:Name,Values=$VPC_NAME" --query 'Vpcs[0].VpcId' --output text)
if [ "$VPC" != "None" ] && [ -n "$VPC" ]; then
  log "VPC $VPC_NAME ($VPC)"
  # ENIs que sobraram de Load Balancer/EKS impedem a remoção — espera liberarem
  for _ in $(seq 1 30); do
    n=$(aws_ ec2 describe-network-interfaces --filters "Name=vpc-id,Values=$VPC" --query 'length(NetworkInterfaces)' --output text)
    [ "$n" = 0 ] && break; sleep 10
  done
  for sg in $(aws_ ec2 describe-security-groups --filters "Name=vpc-id,Values=$VPC" \
      --query 'SecurityGroups[?GroupName!=`default`].GroupId' --output text); do
    # remove regras que referenciam outros SGs antes de apagar
    aws_ ec2 revoke-security-group-ingress --group-id "$sg" \
      --ip-permissions "$(aws_ ec2 describe-security-groups --group-ids "$sg" --query 'SecurityGroups[0].IpPermissions' --output json)" >/dev/null 2>&1 || true
  done
  for sg in $(aws_ ec2 describe-security-groups --filters "Name=vpc-id,Values=$VPC" \
      --query 'SecurityGroups[?GroupName!=`default`].GroupId' --output text); do
    aws_ ec2 delete-security-group --group-id "$sg" && ok "SG $sg removido"
  done
  for igw in $(aws_ ec2 describe-internet-gateways --filters "Name=attachment.vpc-id,Values=$VPC" --query 'InternetGateways[].InternetGatewayId' --output text); do
    aws_ ec2 detach-internet-gateway --internet-gateway-id "$igw" --vpc-id "$VPC"
    aws_ ec2 delete-internet-gateway --internet-gateway-id "$igw" && ok "IGW $igw removido"
  done
  for s in $(aws_ ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC" --query 'Subnets[].SubnetId' --output text); do
    aws_ ec2 delete-subnet --subnet-id "$s" && ok "subnet $s removida"
  done
  for rt in $(aws_ ec2 describe-route-tables --filters "Name=vpc-id,Values=$VPC" \
      --query 'RouteTables[?length(Associations[?Main==`true`])==`0`].RouteTableId' --output text); do
    aws_ ec2 delete-route-table --route-table-id "$rt" && ok "route table $rt removida"
  done
  aws_ ec2 delete-vpc --vpc-id "$VPC" && ok "VPC removida" \
    || aviso "Não foi possível apagar a VPC agora. Apague pelo console: VPC -> Your VPCs -> $VPC_NAME -> Delete VPC."
fi

log "Concluído. Confira no painel do Learner Lab e no console (EC2 > Load Balancers, RDS, ElastiCache)."
