#!/bin/sh
# Backup diário dos bancos "financas" (API) e "agente" (histórico do WhatsApp).
# Roda no serviço "backup" do docker-compose.prod.yml; os arquivos ficam em ./backups no servidor.
set -eu

KEEP_DAYS="${BACKUP_KEEP_DAYS:-14}"
mkdir -p /backups

backup() {
  stamp=$(date +%Y-%m-%d_%H%M)
  ok=0
  for db in financas agente; do
    file="/backups/${db}_${stamp}.dump"
    if pg_dump -h db -U postgres -Fc "$db" > "$file.tmp"; then
      mv "$file.tmp" "$file"
      echo "$(date -Iseconds) backup ok: $file ($(du -h "$file" | cut -f1))"
    else
      rm -f "$file.tmp"
      echo "$(date -Iseconds) ERRO no backup de $db" >&2
      ok=1
    fi
  done
  return $ok
}

while true; do
  until pg_isready -h db -U postgres -q; do sleep 5; done
  # Se falhar, tenta de novo em 10 minutos em vez de esperar o dia seguinte.
  if backup; then
    find /backups -name '*.dump' -mtime +"$KEEP_DAYS" -delete
    sleep 86400
  else
    sleep 600
  fi
done
