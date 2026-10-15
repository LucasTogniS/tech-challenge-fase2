#!/usr/bin/env bash
# Confere ferramentas, credenciais do Learner Lab e o que já existe da Fase 2.
. "$(dirname "$0")/lib.sh"

log "Ferramentas"
for cmd in aws docker kubectl openssl; do
  command -v "$cmd" >/dev/null && ok "$cmd" || falha "$cmd não encontrado no PATH"
done
command -v hey >/dev/null && ok "hey (teste de carga)" || aviso "hey não encontrado — só necessário para a demo de carga"
docker info >/dev/null 2>&1 && ok "Docker Desktop rodando" || falha "Docker Desktop não está rodando"

log "Credenciais da AWS"
if ! ident=$(aws_ sts get-caller-identity --query '[Account,Arn]' --output text 2>&1); then
  falha "Sessão inválida ou expirada. No Learner Lab: Start Lab -> AWS Details -> Show (AWS CLI) e
       cole o bloco em ~/.aws/credentials (as credenciais duram ~4h)."
fi
ok "Conta/identidade: $ident"
ok "Região: $AWS_REGION"

log "Recursos da Fase 2 já existentes"
vpc=$(aws_ ec2 describe-vpcs --filters "Name=tag:Name,Values=$VPC_NAME" --query 'Vpcs[0].VpcId' --output text)
echo "    VPC $VPC_NAME: $vpc"
echo "    EKS $CLUSTER: $(aws_ eks describe-cluster --name "$CLUSTER" --query cluster.status --output text 2>/dev/null || echo 'não existe')"
for db in "${!RDS_DB[@]}"; do
  echo "    RDS $db: $(aws_ rds describe-db-instances --db-instance-identifier "$db" --query 'DBInstances[0].DBInstanceStatus' --output text 2>/dev/null || echo 'não existe')"
done
echo "    ElastiCache $CACHE_ID: $(aws_ elasticache describe-cache-clusters --cache-cluster-id "$CACHE_ID" --query 'CacheClusters[0].CacheClusterStatus' --output text 2>/dev/null || echo 'não existe')"
echo "    DynamoDB $DDB_TABLE: $(aws_ dynamodb describe-table --table-name "$DDB_TABLE" --query Table.TableStatus --output text 2>/dev/null || echo 'não existe')"
echo "    SQS $SQS_QUEUE: $(aws_ sqs get-queue-url --queue-name "$SQS_QUEUE" --query QueueUrl --output text 2>/dev/null || echo 'não existe')"

log "Recursos com cobrança contínua na conta (qualquer fase)"
echo "    Instâncias EC2 rodando: $(aws_ ec2 describe-instances --filters Name=instance-state-name,Values=running --query 'length(Reservations[].Instances[])' --output text)"
echo "    Instâncias RDS: $(aws_ rds describe-db-instances --query 'join(`, `, DBInstances[].join(`:`, [DBInstanceIdentifier, DBInstanceStatus]))' --output text)"
aviso "Confira o crédito restante no painel do Learner Lab antes de começar."
