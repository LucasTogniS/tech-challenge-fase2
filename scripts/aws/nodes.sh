#!/usr/bin/env bash
# Desliga ou religa as máquinas do node group sem destruir o resto da infraestrutura.
#   ./scripts/aws/nodes.sh desligar   -> 0 nós (para de cobrar EC2 entre sessões)
#   ./scripts/aws/nodes.sh ligar      -> volta para 1/2/4, libera o IMDS e reinicia os serviços
. "$(dirname "$0")/lib.sh"

escalar() {
  aws_ eks update-nodegroup-config --cluster-name "$CLUSTER" --nodegroup-name "$NODEGROUP" \
    --scaling-config "minSize=$1,desiredSize=$2,maxSize=4" --query 'update.status' --output text | sed 's/^/    /'
  aws eks wait nodegroup-active --cluster-name "$CLUSTER" --nodegroup-name "$NODEGROUP" --region "$AWS_REGION"
}

case "${1:-}" in
  desligar)
    log "Node group $NODEGROUP -> 0 nós"
    escalar 0 0
    ok "Pedido aceito; as máquinas são encerradas em 1 a 2 minutos"
    ;;
  ligar)
    log "Node group $NODEGROUP -> mín 1 / desejado 2 / máx 4"
    escalar 1 2
    aws_ eks update-kubeconfig --name "$CLUSTER" --region "$AWS_REGION" --alias "$CLUSTER" >/dev/null
    log "Aguardando 2 nós Ready"
    for _ in $(seq 1 60); do
      [ "$(kubectl get nodes --no-headers 2>/dev/null | grep -c ' Ready')" -ge 2 ] && break
      sleep 10
    done
    kubectl get nodes
    log "Metadados da instância acessíveis aos pods"
    liberar_imds_para_pods
    log "Reiniciando os serviços que usam SQS e DynamoDB"
    kubectl -n togglemaster-evaluation rollout restart deployment/evaluation-service
    kubectl -n togglemaster-analytics rollout restart deployment/analytics-service
    for ns in auth flag targeting evaluation analytics; do
      kubectl -n "togglemaster-$ns" rollout status deployment --timeout=300s
    done
    ok "$(load_balancer_url)"
    log "Pronto. Teste: ./scripts/aws/demo/smoke-test.sh"
    ;;
  *) falha "Uso: $0 desligar | ligar" ;;
esac
