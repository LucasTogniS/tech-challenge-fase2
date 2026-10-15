#!/usr/bin/env bash
# Sobe o ToggleMaster num cluster Kubernetes local (kind), com os mesmos manifestos
# que vão para o EKS. Uso (Git Bash, na raiz do repositório):  ./scripts/kind-up.sh
set -euo pipefail
cd "$(dirname "$0")/.."

CLUSTER=togglemaster-fase2
INGRESS_NGINX_VERSION=controller-v1.12.1
METRICS_SERVER_VERSION=v0.7.2
SERVICES="auth-service flag-service targeting-service evaluation-service analytics-service"

[ -f .env ] || { echo "Crie o .env a partir do .env.example primeiro."; exit 1; }
set -a; . ./.env; set +a

echo "==> Cluster kind"
if ! kind get clusters | grep -qx "$CLUSTER"; then
  kind create cluster --config k8s/overlays/kind/kind-cluster.yaml
fi
kubectl config use-context "kind-$CLUSTER" >/dev/null

echo "==> Nginx Ingress Controller"
kubectl apply -f "https://raw.githubusercontent.com/kubernetes/ingress-nginx/$INGRESS_NGINX_VERSION/deploy/static/provider/kind/deploy.yaml"

echo "==> Metrics Server (necessário para o HPA)"
kubectl apply -f "https://github.com/kubernetes-sigs/metrics-server/releases/download/$METRICS_SERVER_VERSION/components.yaml"
# No kind os kubelets usam certificado autoassinado; no EKS este patch não é necessário
kubectl -n kube-system patch deployment metrics-server --type=json \
  -p '[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]' 2>/dev/null || true

echo "==> Build das imagens e carga no cluster"
docker compose build
for s in $SERVICES; do
  kind load docker-image "togglemaster-fase2/$s:local" --name "$CLUSTER"
done

echo "==> Secrets do overlay kind (gerados a partir do .env)"
ENV_DIR=k8s/overlays/kind/env
PG="togglemaster:$POSTGRES_PASSWORD@postgres.togglemaster-deps:5432"
SQS_URL="http://elasticmq.togglemaster-deps:9324/000000000000/togglemaster-fase2-events"
FAKE_AWS="AWS_ACCESS_KEY_ID=local
AWS_SECRET_ACCESS_KEY=local"
printf 'POSTGRES_PASSWORD=%s\n' "$POSTGRES_PASSWORD" > "$ENV_DIR/deps.env"
printf 'DATABASE_URL=postgres://%s/auth_db?sslmode=disable\nMASTER_KEY=%s\nSERVICE_API_KEY=%s\n' "$PG" "$MASTER_KEY" "$SERVICE_API_KEY" > "$ENV_DIR/auth-service.env"
printf 'DATABASE_URL=postgres://%s/flag_db\n' "$PG" > "$ENV_DIR/flag-service.env"
printf 'DATABASE_URL=postgres://%s/targeting_db\n' "$PG" > "$ENV_DIR/targeting-service.env"
printf 'REDIS_URL=redis://redis.togglemaster-deps:6379\nSERVICE_API_KEY=%s\nAWS_SQS_URL=%s\n%s\n' "$SERVICE_API_KEY" "$SQS_URL" "$FAKE_AWS" > "$ENV_DIR/evaluation-service.env"
printf 'AWS_SQS_URL=%s\n%s\n' "$SQS_URL" "$FAKE_AWS" > "$ENV_DIR/analytics-service.env"

echo "==> Aguardando o Ingress Controller"
kubectl -n ingress-nginx wait --for=condition=ready pod -l app.kubernetes.io/component=controller --timeout=180s

echo "==> Aplicando os manifestos"
# Os Jobs são imutáveis: remove os anteriores para reaplicar
kubectl delete job --all -n togglemaster-auth -n togglemaster-flag -n togglemaster-targeting --ignore-not-found >/dev/null 2>&1 || true
kubectl apply -k k8s/overlays/kind

echo "==> Aguardando os pods"
for s in $SERVICES; do
  kubectl -n "togglemaster-${s%%-*}" rollout status "deployment/$s" --timeout=300s
done

echo
echo "Pronto. Ingress em http://localhost:8080  (ex: curl http://localhost:8080/auth/health)"
