#!/usr/bin/env bash
# Exercita o fluxo completo pelo Load Balancer do Ingress:
# cria chave -> cria flag -> cria regra de 50% -> avalia vários usuários.
. "$(dirname "$0")/../lib.sh"
carregar_segredos

URL=$(load_balancer_url)
FLAG=${FLAG:-enable-new-dashboard}
log "Load Balancer: $URL"

log "Health checks via Ingress"
for p in /auth/health /analytics/health; do
  printf '    GET %-18s -> %s\n' "$p" "$(curl -s "$URL$p")"
done

log "POST /auth/admin/keys (protegido pela MASTER_KEY)"
KEY=$(curl -s -X POST "$URL/auth/admin/keys" \
  -H "Authorization: Bearer $MASTER_KEY" -H "Content-Type: application/json" \
  -d '{"name":"demo-video"}' | sed -n 's/.*"key":"\([^"]*\)".*/\1/p')
[ -n "$KEY" ] || falha "Não foi possível criar a chave de API."
ok "chave criada: ${KEY:0:14}..."

log "POST /flags"
curl -s -X POST "$URL/flags" -H "Authorization: Bearer $KEY" -H "Content-Type: application/json" \
  -d "{\"name\":\"$FLAG\",\"description\":\"Novo dashboard\",\"is_enabled\":true}"; echo

log "POST /rules (50% dos usuários)"
curl -s -X POST "$URL/rules" -H "Authorization: Bearer $KEY" -H "Content-Type: application/json" \
  -d "{\"flag_name\":\"$FLAG\",\"is_enabled\":true,\"rules\":{\"type\":\"PERCENTAGE\",\"value\":50}}"; echo

log "GET /flags sem chave (deve ser 401)"
curl -s -o /dev/null -w "    HTTP %{http_code}\n" "$URL/flags"

log "GET /evaluate para 8 usuários"
for u in ana bruno carla diego elisa fabio gabi hugo; do
  printf '    %s\n' "$(curl -s "$URL/evaluate?user_id=$u&flag_name=$FLAG")"
done
echo
ok "Cada avaliação gerou um evento no SQS -> analytics-service -> DynamoDB"
