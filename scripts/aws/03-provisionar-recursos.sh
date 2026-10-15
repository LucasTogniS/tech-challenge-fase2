#!/usr/bin/env bash
# Provisiona os recursos gerenciados que os microsserviços usam:
#   3x RDS PostgreSQL, 1x ElastiCache Redis, 1x DynamoDB, 1x SQS Standard
#   + Security Groups e subnet groups.
#
# É a alternativa por linha de comando aos passos de console do guia — os nomes
# são os mesmos, então os scripts seguintes funcionam com qualquer um dos caminhos.
# Pode ser executado de novo: o que já existe é reaproveitado.
#
# Pré-requisito: VPC da Fase 2 criada e cluster EKS ACTIVE (os Security Groups dos
# bancos liberam acesso só para o Security Group do cluster, que o EKS cria).
. "$(dirname "$0")/lib.sh"
carregar_segredos

VPC=$(vpc_id)
PRIV=$(subnets privadas)

log "Aguardando o cluster EKS ficar ACTIVE (precisamos do Security Group dele)"
aws eks wait cluster-active --name "$CLUSTER" || falha "Cluster $CLUSTER não existe ou falhou. Crie pelo console (guia, passo 3)."
CLUSTER_SG=$(cluster_sg)
ok "Security Group do cluster: $CLUSTER_SG"

# --- Security Groups: banco só aceita conexão vinda dos nós do cluster ---
criar_sg() {  # nome porta descrição
  local id
  id=$(sg_id "$1")
  if [ "$id" = "None" ] || [ -z "$id" ]; then
    id=$(aws_ ec2 create-security-group --group-name "$1" --description "$3" --vpc-id "$VPC" \
      --tag-specifications "ResourceType=security-group,Tags=[{Key=Name,Value=$1},{Key=Project,Value=togglemaster},{Key=Phase,Value=fase2}]" \
      --query GroupId --output text)
    aws_ ec2 authorize-security-group-ingress --group-id "$id" --protocol tcp --port "$2" --source-group "$CLUSTER_SG" >/dev/null
    ok "$1 ($id): entrada $2 somente do SG do cluster"
  else
    ok "$1 ($id) já existe"
  fi
  echo "$id" > "/tmp/$1.id"
}
log "Security Groups"
criar_sg "$SG_RDS"   5432 "PostgreSQL (RDS) - acesso somente do cluster EKS"
criar_sg "$SG_REDIS" 6379 "Redis (ElastiCache) - acesso somente do cluster EKS"
RDS_SG_ID=$(cat "/tmp/$SG_RDS.id"); REDIS_SG_ID=$(cat "/tmp/$SG_REDIS.id")

# --- Subnet groups (bancos nas subnets privadas) ---
log "Subnet groups"
if ! aws_ rds describe-db-subnet-groups --db-subnet-group-name "$DB_SUBNET_GROUP" >/dev/null 2>&1; then
  aws_ rds create-db-subnet-group --db-subnet-group-name "$DB_SUBNET_GROUP" \
    --db-subnet-group-description "Subnets privadas - ToggleMaster Fase 2" --subnet-ids $PRIV >/dev/null
fi
ok "$DB_SUBNET_GROUP"
if ! aws_ elasticache describe-cache-subnet-groups --cache-subnet-group-name "$CACHE_SUBNET_GROUP" >/dev/null 2>&1; then
  aws_ elasticache create-cache-subnet-group --cache-subnet-group-name "$CACHE_SUBNET_GROUP" \
    --cache-subnet-group-description "Subnets privadas - ToggleMaster Fase 2" --subnet-ids $PRIV >/dev/null
fi
ok "$CACHE_SUBNET_GROUP"

# --- RDS (3 instâncias independentes) ---
log "RDS PostgreSQL ($DB_CLASS, ${DB_MAJOR_VERSION}.x, 20 GB gp2, Single-AZ, privado)"
PG_VERSION=$(aws_ rds describe-db-engine-versions --engine postgres --engine-version "$DB_MAJOR_VERSION" \
  --default-only --query 'DBEngineVersions[0].EngineVersion' --output text)
for db in "${!RDS_DB[@]}"; do
  if aws_ rds describe-db-instances --db-instance-identifier "$db" >/dev/null 2>&1; then
    ok "$db já existe"; continue
  fi
  aws_ rds create-db-instance \
    --db-instance-identifier "$db" \
    --db-name "${RDS_DB[$db]}" \
    --engine postgres --engine-version "$PG_VERSION" \
    --db-instance-class "$DB_CLASS" \
    --allocated-storage 20 --storage-type gp2 \
    --master-username "$DB_USER" --master-user-password "$DB_PASSWORD" \
    --db-subnet-group-name "$DB_SUBNET_GROUP" \
    --vpc-security-group-ids "$RDS_SG_ID" \
    --no-publicly-accessible --no-multi-az \
    --backup-retention-period 0 \
    --no-enable-performance-insights \
    --tags $TAGS_PROJETO >/dev/null
  ok "$db (banco ${RDS_DB[$db]}) em criação"
done

# --- ElastiCache Redis ---
log "ElastiCache Redis ($CACHE_NODE_TYPE, 1 nó)"
if aws_ elasticache describe-cache-clusters --cache-cluster-id "$CACHE_ID" >/dev/null 2>&1; then
  ok "$CACHE_ID já existe"
else
  aws_ elasticache create-cache-cluster \
    --cache-cluster-id "$CACHE_ID" \
    --engine redis --cache-node-type "$CACHE_NODE_TYPE" --num-cache-nodes 1 \
    --cache-subnet-group-name "$CACHE_SUBNET_GROUP" \
    --security-group-ids "$REDIS_SG_ID" \
    --tags $TAGS_PROJETO >/dev/null
  ok "$CACHE_ID em criação"
fi

# --- DynamoDB ---
log "DynamoDB"
if aws_ dynamodb describe-table --table-name "$DDB_TABLE" >/dev/null 2>&1; then
  ok "$DDB_TABLE já existe"
else
  aws_ dynamodb create-table --table-name "$DDB_TABLE" \
    --attribute-definitions AttributeName=event_id,AttributeType=S \
    --key-schema AttributeName=event_id,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST \
    --tags Key=Project,Value=togglemaster Key=Phase,Value=fase2 >/dev/null
  ok "$DDB_TABLE criada (chave event_id, on-demand)"
fi

# --- SQS ---
log "SQS Standard"
aws_ sqs create-queue --queue-name "$SQS_QUEUE" --tags Project=togglemaster,Phase=fase2 \
  --query QueueUrl --output text | sed 's/^/    ✔ /'

log "Aguardando RDS e ElastiCache ficarem disponíveis (5 a 15 minutos)"
for db in "${!RDS_DB[@]}"; do
  aws rds wait db-instance-available --db-instance-identifier "$db" && ok "$db disponível"
done
aws elasticache wait cache-cluster-available --cache-cluster-id "$CACHE_ID" && ok "$CACHE_ID disponível"
aws dynamodb wait table-exists --table-name "$DDB_TABLE" && ok "$DDB_TABLE ativa"

log "Pronto. Próximo passo: ./scripts/aws/04-gerar-config-k8s.sh"
