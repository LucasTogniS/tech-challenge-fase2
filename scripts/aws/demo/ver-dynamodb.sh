#!/usr/bin/env bash
# Mostra quantos eventos o analytics-service gravou no DynamoDB e alguns exemplos.
. "$(dirname "$0")/../lib.sh"

log "Tabela $DDB_TABLE"
echo "    Itens: $(aws_ dynamodb scan --table-name "$DDB_TABLE" --select COUNT --query Count --output text)"
echo
aws_ dynamodb scan --table-name "$DDB_TABLE" --max-items 8 \
  --query 'Items[].[event_id.S, user_id.S, flag_name.S, result.BOOL, timestamp.S]' --output table
