#!/bin/sh
# Cadastra a chave de serviço usada pelo evaluation-service para chamar o
# flag-service e o targeting-service. O banco guarda só o hash SHA-256 —
# o mesmo cálculo que o auth-service faz em hashAPIKey().
set -eu
psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -v key="$SERVICE_API_KEY" <<'SQL'
INSERT INTO api_keys (name, key_hash)
VALUES ('evaluation-service', encode(sha256(convert_to(:'key', 'UTF8')), 'hex'))
ON CONFLICT (key_hash) DO NOTHING;
SQL
