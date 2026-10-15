#!/usr/bin/env bash
# Configuração e funções comuns aos scripts da AWS. Não execute diretamente:
# os demais scripts fazem "source" deste arquivo.
set -euo pipefail

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# --- Nomes (tudo da Fase 2 leva o prefixo, para não se misturar com a Fase 1) ---
PREFIX=togglemaster-fase2
export AWS_REGION=us-east-1
export AWS_DEFAULT_REGION=us-east-1
export AWS_PAGER=""

VPC_NAME="$PREFIX-vpc"            # nome gerado pelo assistente "VPC and more" do console
CLUSTER="$PREFIX"
NODEGROUP="$PREFIX-nodes"

DB_USER=tmadmin
DB_CLASS=db.t3.micro
DB_MAJOR_VERSION=16
# instância RDS -> nome do banco
declare -A RDS_DB=(
  ["$PREFIX-auth-db"]=auth_db
  ["$PREFIX-flag-db"]=flag_db
  ["$PREFIX-targeting-db"]=targeting_db
)

CACHE_ID="$PREFIX-redis"
CACHE_NODE_TYPE=cache.t3.micro
SQS_QUEUE="$PREFIX-events"
DDB_TABLE=ToggleMasterAnalytics   # nome esperado pelo código do analytics-service

SG_RDS="$PREFIX-rds-sg"
SG_REDIS="$PREFIX-redis-sg"
DB_SUBNET_GROUP="$PREFIX-db-subnets"
CACHE_SUBNET_GROUP="$PREFIX-cache-subnets"

ECR_NAMESPACE="$PREFIX"
IMAGE_TAG="${IMAGE_TAG:-v1}"
SERVICES="auth-service flag-service targeting-service evaluation-service analytics-service"

INGRESS_NGINX_VERSION=controller-v1.12.1
METRICS_SERVER_VERSION=v0.7.2

TAGS_PROJETO="Key=Project,Value=togglemaster Key=Phase,Value=fase2"

SEGREDOS="$RAIZ/scripts/aws/.segredos.env"   # ignorado pelo Git

# --- Funções ---

# A AWS CLI no Windows devolve CRLF; o \r quebra comparações no bash
aws_() { aws "$@" | tr -d '\r'; }

log()  { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
ok()   { printf '    \033[32m✔\033[0m %s\n' "$*"; }
aviso(){ printf '    \033[33m!\033[0m %s\n' "$*"; }
falha(){ printf '\n\033[31mERRO:\033[0m %s\n' "$*" >&2; exit 1; }

conta_aws() { aws_ sts get-caller-identity --query Account --output text; }
ecr_registry() { echo "$(conta_aws).dkr.ecr.$AWS_REGION.amazonaws.com"; }

# Senhas e chaves da Fase 2 na AWS: geradas uma vez e reaproveitadas
carregar_segredos() {
  if [ ! -f "$SEGREDOS" ]; then
    {
      echo "# Gerado por scripts/aws — NÃO commitar"
      echo "DB_PASSWORD=$(openssl rand -hex 16)"
      echo "MASTER_KEY=$(openssl rand -hex 24)"
      echo "SERVICE_API_KEY=tm_key_$(openssl rand -hex 32)"
    } > "$SEGREDOS"
    ok "Segredos gerados em scripts/aws/.segredos.env"
  fi
  set -a; . "$SEGREDOS"; set +a
}

vpc_id() {
  local id
  id=$(aws_ ec2 describe-vpcs --filters "Name=tag:Name,Values=$VPC_NAME" --query 'Vpcs[0].VpcId' --output text)
  [ "$id" != "None" ] && [ -n "$id" ] || falha "VPC '$VPC_NAME' não encontrada. Crie-a pelo console (guia, passo 2)."
  echo "$id"
}

# subnets publicas|privadas da VPC da Fase 2 (o assistente põe "public"/"private" no nome)
subnets() {
  local tipo=$1 filtro
  [ "$tipo" = publicas ] && filtro='*public*' || filtro='*private*'
  aws_ ec2 describe-subnets \
    --filters "Name=vpc-id,Values=$(vpc_id)" "Name=tag:Name,Values=$filtro" \
    --query 'Subnets[].SubnetId' --output text
}

cluster_sg() {
  aws_ eks describe-cluster --name "$CLUSTER" \
    --query 'cluster.resourcesVpcConfig.clusterSecurityGroupId' --output text
}

sg_id() {
  aws_ ec2 describe-security-groups \
    --filters "Name=group-name,Values=$1" "Name=vpc-id,Values=$(vpc_id)" \
    --query 'SecurityGroups[0].GroupId' --output text
}

load_balancer_url() {
  local host
  host=$(kubectl -n ingress-nginx get svc ingress-nginx-controller \
    -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)
  [ -n "$host" ] || falha "Load Balancer do Ingress ainda não existe (rode 05-preparar-cluster.sh)."
  echo "http://$host"
}

confirmar() {
  local resp
  read -r -p "    $1 [s/N] " resp
  [ "$resp" = s ] || [ "$resp" = S ]
}
