#!/bin/sh
# Uma instância PostgreSQL, dois bancos isolados: flag_db e targeting_db.
# Cada serviço continua dono do seu próprio schema (database-per-service).
set -eu
for db in flag_db targeting_db; do
  psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d postgres -c "CREATE DATABASE $db"
done
psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d flag_db      -f /schemas/flag-init.sql
psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d targeting_db -f /schemas/targeting-init.sql
