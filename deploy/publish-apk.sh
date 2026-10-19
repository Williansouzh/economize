#!/bin/sh
# Publica o APK de produção em https://economizze.tech/download/economizze.apk (botão da landing page).
# Roda na sua máquina, depois de "flutter build apk --release --dart-define=API_URL=https://economizze.tech".
# O APK não vai para o git: fica em ~/economize/downloads no servidor, montado no Caddy.
#
# Uso: deploy/publish-apk.sh [caminho/do/app-release.apk]
#      SERVER=deploy@outro-host deploy/publish-apk.sh
set -eu

cd "$(dirname "$0")/.."
APK="${1:-mobile/build/app/outputs/flutter-apk/app-release.apk}"
SERVER="${SERVER:-deploy@economizze.tech}"
DIR="economize/downloads"
MIN_ANDROID="7"  # minSdk 24 (padrão do Flutter)

[ -f "$APK" ] || { echo "APK não encontrado: $APK" >&2; exit 1; }
VERSION=$(sed -n 's/^version: *\([^+]*\).*/\1/p' mobile/pubspec.yaml)
SIZE=$(wc -c < "$APK" | tr -d ' ')
SHA256=$(sha256sum "$APK" | cut -d' ' -f1)

echo "Enviando $APK (versão $VERSION, $((SIZE / 1048576)) MB) para $SERVER..."
ssh "$SERVER" "mkdir -p $DIR"
# Envia com nome temporário e troca no fim, para ninguém baixar um arquivo pela metade.
scp -q "$APK" "$SERVER:$DIR/economizze.apk.tmp"
printf '{"version":"%s","size":%s,"sha256":"%s","minAndroid":"%s"}\n' "$VERSION" "$SIZE" "$SHA256" "$MIN_ANDROID" \
  | ssh "$SERVER" "cat > $DIR/version.json.tmp && mv $DIR/economizze.apk.tmp $DIR/economizze.apk && mv $DIR/version.json.tmp $DIR/version.json"
echo "Publicado: https://economizze.tech/download/economizze.apk"
