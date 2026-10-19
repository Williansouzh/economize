#!/bin/sh
# Publica os APKs de produção para o botão de download da landing page:
#   https://economizze.tech/download/economizze.apk            só arm64 (~20 MB, quase todo celular atual)
#   https://economizze.tech/download/economizze-universal.apk  todos os processadores (~55 MB, 32 bits etc.)
# Os APKs não vão para o git: ficam em ~/economize/downloads no servidor, montado no Caddy.
#
# Gere os dois na sua máquina (em mobile/) e depois rode este script da raiz do repositório:
#   flutter build apk --release --dart-define=API_URL=https://economizze.tech
#   cp build/app/outputs/flutter-apk/app-release.apk build/economizze-universal.apk
#   flutter build apk --release --target-platform android-arm64 --android-project-arg=onlyAbi=arm64-v8a \
#     --dart-define=API_URL=https://economizze.tech
#   cp build/app/outputs/flutter-apk/app-release.apk build/economizze-arm64.apk
#
# Não use --split-per-abi: ele muda o versionCode (ex.: 2004 em vez de 4) e depois impede atualizar
# pela versão universal ou pela Google Play.
#
# Uso: deploy/publish-apk.sh            (SERVER=deploy@outro-host para outro servidor)
set -eu

cd "$(dirname "$0")/.."
ARM64="mobile/build/economizze-arm64.apk"
UNIVERSAL="mobile/build/economizze-universal.apk"
SERVER="${SERVER:-deploy@economizze.tech}"
DIR="economize/downloads"
MIN_ANDROID="7"  # minSdk 24 (padrão do Flutter)

for f in "$ARM64" "$UNIVERSAL"; do
  [ -f "$f" ] || { echo "APK não encontrado: $f (veja os comandos no topo do script)" >&2; exit 1; }
done
VERSION=$(sed -n 's/^version: *\([^+]*\).*/\1/p' mobile/pubspec.yaml)
size() { wc -c < "$1" | tr -d ' '; }

echo "Enviando APKs da versão $VERSION para $SERVER..."
ssh "$SERVER" "mkdir -p $DIR"
# Envia com nome temporário e troca no fim, para ninguém baixar um arquivo pela metade.
scp -q "$ARM64" "$SERVER:$DIR/economizze.apk.tmp"
scp -q "$UNIVERSAL" "$SERVER:$DIR/economizze-universal.apk.tmp"
printf '{"version":"%s","size":%s,"universalSize":%s,"sha256":"%s","minAndroid":"%s"}\n' \
  "$VERSION" "$(size "$ARM64")" "$(size "$UNIVERSAL")" "$(sha256sum "$ARM64" | cut -d' ' -f1)" "$MIN_ANDROID" \
  | ssh "$SERVER" "cat > $DIR/version.json.tmp \
      && mv $DIR/economizze.apk.tmp $DIR/economizze.apk \
      && mv $DIR/economizze-universal.apk.tmp $DIR/economizze-universal.apk \
      && mv $DIR/version.json.tmp $DIR/version.json"
echo "Publicado: https://economizze.tech/download/economizze.apk (e economizze-universal.apk)"
