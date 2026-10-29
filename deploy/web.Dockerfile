# Proxy (Caddy) com a landing page (site/, em /) e o app Flutter web (em /app/) dentro.
# Build: docker compose -f docker-compose.prod.yml build caddy (contexto = raiz do repositório)

FROM debian:12-slim AS web
# Mesma versão de Flutter usada no desenvolvimento. Não há imagem oficial por versão,
# então o SDK é baixado do repositório do Flutter na tag exata.
ARG FLUTTER_VERSION=3.47.7
RUN apt-get update \
 && apt-get install -y --no-install-recommends git curl unzip xz-utils ca-certificates \
 && rm -rf /var/lib/apt/lists/*
RUN git clone --depth 1 --branch ${FLUTTER_VERSION} https://github.com/flutter/flutter.git /opt/flutter
ENV PATH="/opt/flutter/bin:${PATH}"
RUN flutter config --no-analytics && flutter precache --web

WORKDIR /src
COPY mobile/pubspec.yaml mobile/pubspec.lock ./
RUN flutter pub get
COPY mobile/ ./
# A API fica no mesmo domínio do app (/api), então a URL base é o próprio domínio.
ARG DOMAIN
RUN test -n "$DOMAIN" || (echo "Defina DOMAIN no .env" && exit 1)
# --no-web-resources-cdn: o CanvasKit vem do próprio domínio, não do CDN do Google (CSP em deploy/security-headers.caddy).
RUN flutter build web --release --base-href /app/ --no-web-resources-cdn --dart-define=API_URL=https://${DOMAIN}

FROM caddy:2.11.7-alpine
COPY deploy/Caddyfile /etc/caddy/Caddyfile
COPY deploy/security-headers.caddy /etc/caddy/security-headers.caddy
COPY site/ /srv/web/
COPY --from=web /src/build/web /srv/web/app
