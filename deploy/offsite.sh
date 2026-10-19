#!/bin/sh
# Cópia dos backups para fora da VPS, criptografada no próprio servidor (restic). Roda no serviço
# "offsite" do docker-compose.prod.yml. Desligado enquanto RESTIC_REPOSITORY estiver vazio.
# Configuração e restauração: docs/DEPLOY.md, seção "Backups".
set -eu

if [ -z "${RESTIC_REPOSITORY:-}" ]; then
  echo "Backup externo desligado (defina RESTIC_REPOSITORY e RESTIC_PASSWORD no .env)."
  while true; do sleep 86400; done
fi
: "${RESTIC_PASSWORD:?defina RESTIC_PASSWORD no .env}"

# Cria o repositório na primeira vez.
restic cat config >/dev/null 2>&1 || restic init

while true; do
  # Envia só o que mudou e guarda 14 dias, como os backups locais: a política de privacidade promete que
  # dados excluídos somem das cópias em até 14 dias.
  if restic backup /backups --tag economizze --host economizze \
     && restic forget --tag economizze --keep-within 14d --prune; then
    echo "$(date -Iseconds) backup externo ok"
  else
    echo "$(date -Iseconds) ERRO no backup externo" >&2
  fi
  sleep 86400
done
