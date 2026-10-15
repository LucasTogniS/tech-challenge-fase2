#!/usr/bin/env bash
# Painel simples para o vídeo: HPAs e pods do evaluation e do analytics a cada 5s.
. "$(dirname "$0")/../lib.sh"
while true; do
  clear
  date '+%H:%M:%S'
  echo
  kubectl get hpa -A
  echo
  kubectl get pods -n togglemaster-evaluation
  kubectl get pods -n togglemaster-analytics --no-headers
  echo
  echo "Fila $SQS_QUEUE: $(aws_ sqs get-queue-attributes --queue-url "$(aws_ sqs get-queue-url --queue-name "$SQS_QUEUE" --query QueueUrl --output text)" \
    --attribute-names ApproximateNumberOfMessages --query Attributes.ApproximateNumberOfMessages --output text) mensagens"
  sleep 5
done
