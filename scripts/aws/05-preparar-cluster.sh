#!/usr/bin/env bash
# Conecta o kubectl ao EKS e instala os componentes de cluster:
#   - Metrics Server (fornece CPU/memória dos pods para o HPA)
#   - Nginx Ingress Controller (cria o Network Load Balancer público)
. "$(dirname "$0")/lib.sh"

log "kubeconfig"
aws_ eks update-kubeconfig --name "$CLUSTER" --region "$AWS_REGION" --alias "$CLUSTER" | sed 's/^/    /'
kubectl get nodes -o wide

NODES_READY=$(kubectl get nodes --no-headers 2>/dev/null | grep -c " Ready" || true)
[ "$NODES_READY" -ge 1 ] || falha "Nenhum nó Ready. O Managed Node Group foi criado (guia, passo 4)?"

log "Metrics Server $METRICS_SERVER_VERSION"
kubectl apply -f "https://github.com/kubernetes-sigs/metrics-server/releases/download/$METRICS_SERVER_VERSION/components.yaml"
kubectl -n kube-system rollout status deployment/metrics-server --timeout=180s

log "Nginx Ingress Controller ($INGRESS_NGINX_VERSION, provider AWS -> Network Load Balancer)"
kubectl apply -f "https://raw.githubusercontent.com/kubernetes/ingress-nginx/$INGRESS_NGINX_VERSION/deploy/static/provider/aws/deploy.yaml"
kubectl -n ingress-nginx wait --for=condition=ready pod -l app.kubernetes.io/component=controller --timeout=300s

log "Aguardando o Load Balancer receber um endereço"
for _ in $(seq 1 60); do
  host=$(kubectl -n ingress-nginx get svc ingress-nginx-controller \
    -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)
  [ -n "$host" ] && break
  sleep 5
done
[ -n "$host" ] || falha "O Load Balancer não recebeu endereço. Veja: kubectl -n ingress-nginx describe svc ingress-nginx-controller"
ok "http://$host  (o DNS pode levar 1 a 3 minutos para propagar)"

log "Pronto. Próximo passo: ./scripts/aws/06-deploy.sh"
