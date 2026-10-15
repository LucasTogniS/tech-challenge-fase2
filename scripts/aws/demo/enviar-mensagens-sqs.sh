#!/usr/bin/env bash
# Enche a fila SQS de eventos para demonstrar o HPA do analytics-service.
# Roda um pod temporário dentro do cluster, com a própria imagem do analytics
# (já tem Python + boto3) e as permissões da LabRole dos nós.
#
# Uso:  ./enviar-mensagens-sqs.sh            (5000 mensagens)
#       N=20000 ./enviar-mensagens-sqs.sh
. "$(dirname "$0")/../lib.sh"

N=${N:-5000}
SQS_URL=$(aws_ sqs get-queue-url --queue-name "$SQS_QUEUE" --query QueueUrl --output text)
IMG="$(ecr_registry)/$ECR_NAMESPACE/analytics-service:$IMAGE_TAG"

PY='
import os, json, datetime, boto3
from concurrent.futures import ThreadPoolExecutor
q, n = os.environ["AWS_SQS_URL"], int(os.environ["N"])
sqs = boto3.client("sqs", region_name="us-east-1")
def lote(i):
    agora = datetime.datetime.utcnow().isoformat() + "Z"
    sqs.send_message_batch(QueueUrl=q, Entries=[
        {"Id": str(j), "MessageBody": json.dumps({
            "user_id": f"carga-{i}-{j}", "flag_name": "enable-new-dashboard",
            "result": (i + j) % 2 == 0, "timestamp": agora})}
        for j in range(10)])
with ThreadPoolExecutor(16) as ex:
    list(ex.map(lote, range(n // 10)))
print(f"{n} mensagens enviadas para {q}")
'

EXTRA_ENV=()
if [ "${USAR_CREDENCIAIS_DA_SESSAO:-0}" = 1 ]; then
  while IFS= read -r linha; do [ -n "$linha" ] && EXTRA_ENV+=("--env=$linha"); done \
    < <(aws configure export-credentials --format env-no-export | tr -d '\r')
fi

log "Enviando $N mensagens para $SQS_QUEUE"
kubectl -n togglemaster-analytics delete pod sqs-carga --ignore-not-found >/dev/null 2>&1
kubectl -n togglemaster-analytics run sqs-carga --rm -i --restart=Never --quiet \
  --image="$IMG" --env="AWS_SQS_URL=$SQS_URL" --env="N=$N" "${EXTRA_ENV[@]}" \
  --command -- python -c "$PY"
ok "Acompanhe o HPA: ./scripts/aws/demo/observar-hpa.sh"
