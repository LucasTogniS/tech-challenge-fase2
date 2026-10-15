#!/usr/bin/env bash
# Gera carga no evaluation-service para demonstrar o HPA.
# Em outro terminal, acompanhe:  ./scripts/aws/demo/observar-hpa.sh
#
# Uso:  ./carga-evaluation.sh                 (120s, 80 conexões)
#       DURACAO=180s CONEXOES=150 ./carga-evaluation.sh
. "$(dirname "$0")/../lib.sh"
command -v hey >/dev/null || falha "hey não encontrado no PATH."

URL="$(load_balancer_url)/evaluate?user_id=carga&flag_name=${FLAG:-enable-new-dashboard}"
log "hey -z ${DURACAO:-120s} -c ${CONEXOES:-80} $URL"
hey -z "${DURACAO:-120s}" -c "${CONEXOES:-80}" "$URL"
