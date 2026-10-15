#!/usr/bin/env bash
# Aplica os manifestos do overlay AWS no EKS e espera tudo ficar pronto.
. "$(dirname "$0")/lib.sh"

for f in auth-service flag-service targeting-service evaluation-service analytics-service; do
  [ -f "$RAIZ/k8s/overlays/aws/env/$f.env" ] || falha "Falta k8s/overlays/aws/env/$f.env — rode 04-gerar-config-k8s.sh."
done

CONTA=$(conta_aws)

log "Removendo Jobs de migração anteriores (Jobs são imutáveis)"
for ns in togglemaster-auth togglemaster-flag togglemaster-targeting; do
  kubectl -n "$ns" delete job --all --ignore-not-found 2>/dev/null || true
done

log "Aplicando k8s/overlays/aws (imagens de $CONTA.dkr.ecr.$AWS_REGION.amazonaws.com)"
kubectl kustomize "$RAIZ/k8s/overlays/aws" | sed "s/CONTA/$CONTA/g" | kubectl apply -f -

log "Migrações dos bancos (Jobs)"
for s in auth-service flag-service targeting-service; do
  ns="togglemaster-${s%%-*}"
  kubectl -n "$ns" wait --for=condition=complete "job/$s-migration" --timeout=300s && ok "$s-migration concluído"
done

log "Rollout dos Deployments"
for s in $SERVICES; do
  kubectl -n "togglemaster-${s%%-*}" rollout status "deployment/$s" --timeout=300s
done

log "Estado"
kubectl get pods -A -l app.kubernetes.io/part-of=togglemaster
kubectl get hpa -A
echo
ok "URL pública: $(load_balancer_url)"
log "Teste rápido: ./scripts/aws/demo/smoke-test.sh"
