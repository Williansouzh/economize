#!/bin/sh
# Backup diário dos bancos "financas" (API) e "agente" (histórico do WhatsApp).
# Roda no serviço "backup" do docker-compose.prod.yml; os arquivos ficam em ./backups no servidor.
set -eu

KEEP_DAYS="${BACKUP_KEEP_DAYS:-14}"
mkdir -p /backups

while true; do
  stamp=$(date +%Y-%m-%d_%H%M)
  for db in financas agente; do
    file="/backups/${db}_${stamp}.dump"
    if pg_dump -h db -U postgres -Fc "$db" > "$file.tmp"; then
      mv "$file.tmp" "$file"
      echo "$(date -Iseconds) backup ok: $file ($(du -h "$file" | cut -f1))"
    else
      rm -f "$file.tmp"
      echo "$(date -Iseconds) ERRO no backup de $db" >&2
    fi
  done
  find /backups -name '*.dump' -mtime +"$KEEP_DAYS" -delete
  sleep 86400
done
