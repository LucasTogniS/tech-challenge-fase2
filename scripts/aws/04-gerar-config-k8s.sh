#!/usr/bin/env bash
# Coleta os endpoints reais (RDS, ElastiCache, SQS) e gera os arquivos de Secret
# do overlay AWS em k8s/overlays/aws/env/*.env (ignorados pelo Git).
#
# Funciona tanto com recursos criados pelo console quanto pelo script 03,
# desde que os nomes sejam os do guia.
#
# Uso:  ./04-gerar-config-k8s.sh
#       USAR_CREDENCIAIS_DA_SESSAO=1 ./04-gerar-config-k8s.sh
#         -> plano B: injeta as credenciais temporárias do Learner Lab nos Secrets do
#            evaluation e do analytics, caso os pods não consigam usar a LabRole dos nós.
#            Expiram com a sessão (~4h): rode de novo e reaplique após renovar.
. "$(dirname "$0")/lib.sh"
carregar_segredos

ENV_DIR="$RAIZ/k8s/overlays/aws/env"

rds_endpoint() {
  aws_ rds describe-db-instances --db-instance-identifier "$1" \
    --query 'DBInstances[0].Endpoint.Address' --output text 2>/dev/null \
    || falha "RDS $1 não encontrado."
}

log "Endpoints"
AUTH_DB=$(rds_endpoint "$PREFIX-auth-db");           ok "auth      $AUTH_DB"
FLAG_DB=$(rds_endpoint "$PREFIX-flag-db");           ok "flag      $FLAG_DB"
TARGETING_DB=$(rds_endpoint "$PREFIX-targeting-db"); ok "targeting $TARGETING_DB"
REDIS=$(aws_ elasticache describe-cache-clusters --cache-cluster-id "$CACHE_ID" --show-cache-node-info \
  --query 'CacheClusters[0].CacheNodes[0].Endpoint.Address' --output text) || falha "ElastiCache $CACHE_ID não encontrado."
ok "redis     $REDIS"
SQS_URL=$(aws_ sqs get-queue-url --queue-name "$SQS_QUEUE" --query QueueUrl --output text) || falha "Fila $SQS_QUEUE não encontrada."
ok "sqs       $SQS_URL"
aws_ dynamodb describe-table --table-name "$DDB_TABLE" --query Table.TableStatus --output text >/dev/null \
  || falha "Tabela $DDB_TABLE não encontrada."
ok "dynamodb  $DDB_TABLE"

CRED=""
if [ "${USAR_CREDENCIAIS_DA_SESSAO:-0}" = 1 ]; then
  aviso "Incluindo credenciais temporárias da sessão nos Secrets (plano B)"
  CRED=$(aws configure export-credentials --format env-no-export | tr -d '\r')
fi

log "Gerando k8s/overlays/aws/env/*.env"
cat > "$ENV_DIR/auth-service.env" <<EOF
DATABASE_URL=postgres://$DB_USER:$DB_PASSWORD@$AUTH_DB:5432/auth_db
MASTER_KEY=$MASTER_KEY
SERVICE_API_KEY=$SERVICE_API_KEY
EOF
cat > "$ENV_DIR/flag-service.env" <<EOF
DATABASE_URL=postgres://$DB_USER:$DB_PASSWORD@$FLAG_DB:5432/flag_db
EOF
cat > "$ENV_DIR/targeting-service.env" <<EOF
DATABASE_URL=postgres://$DB_USER:$DB_PASSWORD@$TARGETING_DB:5432/targeting_db
EOF
cat > "$ENV_DIR/evaluation-service.env" <<EOF
REDIS_URL=redis://$REDIS:6379
SERVICE_API_KEY=$SERVICE_API_KEY
AWS_SQS_URL=$SQS_URL
${CRED}
EOF
cat > "$ENV_DIR/analytics-service.env" <<EOF
AWS_SQS_URL=$SQS_URL
${CRED}
EOF
ok "5 arquivos gerados"

log "Pronto. Próximo passo: ./scripts/aws/05-preparar-cluster.sh"
