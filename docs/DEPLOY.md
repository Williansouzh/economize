# Deploy em produção

Tudo roda numa VPS com Docker: API, agente do WhatsApp, PostgreSQL, Caddy (HTTPS automático e app web)
e um serviço de backup. Só as portas 80 e 443 ficam abertas.

```
https://SEU-DOMINIO/          → landing page e páginas públicas (pasta site/)
https://SEU-DOMINIO/app/      → app Flutter web
https://SEU-DOMINIO/download/economizze.apk → APK (deploy/publish-apk.sh)
https://SEU-DOMINIO/api/...   → API .NET
https://SEU-DOMINIO/webhook   → agente (URL cadastrada na Meta)
https://SEU-DOMINIO/health/api, /health/agent → checagem de saúde
```

Arquivos: [`docker-compose.prod.yml`](../docker-compose.prod.yml), [`deploy/Caddyfile`](../deploy/Caddyfile),
[`deploy/web.Dockerfile`](../deploy/web.Dockerfile), [`deploy/backup.sh`](../deploy/backup.sh),
[`deploy/publish-apk.sh`](../deploy/publish-apk.sh), [`site/`](../site/),
[`.env.prod.example`](../.env.prod.example).

## 1. Domínio

Registre um domínio (ex.: em [registro.br](https://registro.br), ~R$ 40/ano para `.com.br`).
Depois de contratar a VPS (passo 2), crie no painel de DNS um registro **A** apontando para o IP dela:

| Tipo | Nome | Valor |
|---|---|---|
| A | `financas` (ou `@` para o domínio raiz) | IP da VPS |

Com isso o endereço fica `financas.seudominio.com.br`. Confira com `dig +short financas.seudominio.com.br`
antes de subir: o Caddy só consegue o certificado HTTPS quando o DNS já aponta para o servidor.

> Sem domínio ainda? Para testar, use `IP-COM-HIFENS.sslip.io` (ex.: `203-0-113-10.sslip.io`), que já
> resolve para o IP sem cadastro. Funciona com HTTPS, mas troque por um domínio próprio antes de publicar
> o app: a URL fica gravada no APK e na Play.

## 2. VPS

- **Tamanho:** 2 vCPU e **4 GB de RAM** no mínimo (o Whisper `small` usa ~1 GB ao transcrever áudios),
  40 GB de disco. Ubuntu 24.04.
- **Onde:** qualquer provedor serve (Hetzner, Contabo, DigitalOcean, Hostinger, Magalu Cloud…).
  Região no Brasil ou nos EUA (leste) dá a menor latência para o app e para a Meta.
- Crie o servidor com **login por chave SSH** (não por senha).

## 3. Preparar o servidor

```bash
ssh root@IP-DA-VPS

# Atualizações automáticas de segurança e firewall
apt update && apt upgrade -y
apt install -y unattended-upgrades ufw git
ufw allow OpenSSH && ufw allow 80/tcp && ufw allow 443 && ufw --force enable

# Docker
curl -fsSL https://get.docker.com | sh

# Usuário sem root para rodar o projeto
adduser --disabled-password --gecos "" deploy
usermod -aG docker deploy
mkdir -p /home/deploy/.ssh && cp ~/.ssh/authorized_keys /home/deploy/.ssh/
chown -R deploy:deploy /home/deploy/.ssh

# Desliga login por senha e de root via SSH
sed -i 's/^#\?PasswordAuthentication .*/PasswordAuthentication no/; s/^#\?PermitRootLogin .*/PermitRootLogin no/' /etc/ssh/sshd_config
systemctl restart ssh
```

> O Docker publica portas por fora do `ufw`. Por isso o `docker-compose.prod.yml` só expõe o Caddy;
> banco, API e agente não têm `ports:`.

## 4. Subir

```bash
ssh deploy@IP-DA-VPS
docker network create --subnet 172.30.0.0/24 edge   # uma vez por VPS (ver seção abaixo)
git clone https://github.com/Williansouzh/economize.git && cd economize
cp .env.prod.example .env && chmod 600 .env
nano .env   # preencha (veja abaixo)
docker compose -f docker-compose.prod.yml up -d --build
```

O primeiro build leva de 10 a 20 minutos (baixa o Flutter para compilar o app web).

**Preenchendo o `.env`:**

| Variável | Valor |
|---|---|
| `DOMAIN` | O domínio do passo 1, sem `https://` |
| `ACME_EMAIL` | Seu e-mail (avisos do Let's Encrypt) |
| `POSTGRES_PASSWORD`, `JWT_KEY`, `AGENT_API_KEY` | Uma saída de `openssl rand -hex 32` para cada |
| `DEEPSEEK_API_KEY` | Uma chave **nova** criada em platform.deepseek.com/api_keys (não reaproveite a de desenvolvimento) |
| `WHATSAPP_*` | Do passo 6. Pode deixar vazio no começo: o app funciona sem o WhatsApp. |

**Conferindo:**

```bash
docker compose -f docker-compose.prod.yml ps        # todos "running"
docker compose -f docker-compose.prod.yml logs -f caddy api agent
curl https://SEU-DOMINIO/health/api                 # {"status":"ok"}
curl https://SEU-DOMINIO/health/agent               # {"status":"ok"}
```

Abra `https://SEU-DOMINIO` no navegador: é a landing page. O app web fica em `https://SEU-DOMINIO/app/`;
crie sua conta por ele.

### Outros sistemas na mesma VPS

O Caddy deste projeto é a única porta de entrada da VPS (80/443). Outro sistema
hospedado aqui (hoje, o Floruna) não publica portas: ele entra na rede docker
`edge` e deixa os arquivos de site dele numa pasta do host, que o Caddy importa:

- `*.caddy`: blocos de site, importados no fim do Caddyfile;
- `*.global`: opções globais (ex.: `on_demand_tls`), importadas no bloco global.

```bash
# .env deste projeto
EDGE_SITES_DIR=/home/deploy/caddy-sites

# Depois de mudar um arquivo da pasta (sem derrubar nada):
docker compose -f docker-compose.prod.yml exec caddy caddy reload --config /etc/caddy/Caddyfile
```

A subnet da rede `edge` é fixa porque os outros sistemas confiam no
`X-Forwarded-For` vindo dela. Não recrie a rede com outra faixa.

## 5. App Android (APK e Google Play)

Na sua máquina, com o domínio já no ar.

**Chave de assinatura** (uma vez só). Guarde o arquivo `.jks` e as senhas num gerenciador de senhas
e num backup fora do PC: **se perder a chave, não dá para atualizar o app na Play** com o mesmo cadastro.

```bash
cd mobile/android
~/development/jdk-21/bin/keytool -genkeypair -v -keystore app/upload-keystore.jks \
  -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

Crie `mobile/android/key.properties` (já está no `.gitignore`, assim como o `.jks`):

```properties
storePassword=SENHA-DO-KEYSTORE
keyPassword=SENHA-DA-CHAVE
keyAlias=upload
storeFile=upload-keystore.jks
```

**Builds** (a URL da API fica gravada no app):

```bash
cd mobile
# APK para instalar direto
flutter build apk --release --dart-define=API_URL=https://SEU-DOMINIO
#   → build/app/outputs/flutter-apk/app-release.apk

# App Bundle para a Google Play
flutter build appbundle --release --dart-define=API_URL=https://SEU-DOMINIO
#   → build/app/outputs/bundle/release/app-release.aab
```

**Botão "Baixar para Android" da landing page:** a página oferece um APK só para arm64 (~20 MB, quase
todo celular atual) e um universal (~55 MB) para aparelhos de 32 bits. Os comandos para gerar os dois
estão no topo de [`deploy/publish-apk.sh`](../deploy/publish-apk.sh); depois rode na sua máquina

```bash
deploy/publish-apk.sh            # envia os APKs para ~/economize/downloads no servidor
```

Não use `--split-per-abi`: ele muda o `versionCode` e depois bloqueia as atualizações. O script troca os
arquivos de uma vez (ninguém baixa um APK pela metade) e grava `version.json`, que a landing page usa
para mostrar versão e tamanho. O APK não vai para o git; a pasta `downloads/` é montada
no Caddy. Não precisa reiniciar nada.

A cada nova versão, aumente `version:` no `mobile/pubspec.yaml` (ex.: `1.0.1+2`; o número depois do `+`
precisa crescer sempre).

**Google Play:**

1. Crie a conta de desenvolvedor em [play.google.com/console](https://play.google.com/console) (US$ 25, uma vez).
   Contas pessoais novas precisam de um **teste fechado com 12 testadores por 14 dias** antes da produção.
2. O `applicationId` é `tech.economizze.app` (`mobile/android/app/build.gradle.kts`). Depois do primeiro
   envio à Play, ele **nunca** mais pode mudar.
3. Crie o app, envie o `.aab` em **Testes → Teste fechado** e preencha a ficha da loja.
4. Na ficha da loja, informe:
   - **Política de privacidade:** `https://economizze.tech/privacidade.html`
     (fonte: `site/privacidade.html`, publicada junto com a landing page);
   - **Exclusão de conta:** `https://economizze.tech/excluir-conta.html` (o app também tem
     "Excluir minha conta" no menu, RN-30).
   No formulário de **Segurança dos dados**, declare: nome, e-mail, informações financeiras e, para quem
   usa o WhatsApp, número de telefone e mensagens; dados compartilhados com a DeepSeek (IA) e a Meta
   (WhatsApp); criptografia em trânsito; exclusão a pedido. Mantenha coerente com `privacidade.html`.
5. Ative a **Assinatura de apps do Google Play** (padrão): a Google guarda a chave final e a sua vira a
   "chave de upload".

## 6. WhatsApp

Com o domínio no ar, siga [`agent/README.md`](../agent/README.md#configurando-o-whatsapp-cloud-api-oficial-da-meta).
Na Meta, a URL do webhook é `https://SEU-DOMINIO/webhook`.

- Preencha `WHATSAPP_TOKEN`, `WHATSAPP_PHONE_NUMBER_ID`, `WHATSAPP_VERIFY_TOKEN` e **`WHATSAPP_APP_SECRET`**
  no `.env`. Sem o App Secret, o agente recusa todos os webhooks (resposta 503).
- O token temporário dura 24h. Em produção, gere um **token permanente** com um *Usuário do sistema* no
  Business Manager.
- Depois de mudar o `.env`: `docker compose -f docker-compose.prod.yml up -d agent`.

## 7. Atualizar

```bash
ssh deploy@IP-DA-VPS && cd economize
git pull
docker compose -f docker-compose.prod.yml up -d --build
docker image prune -f
```

As migrations do banco rodam sozinhas quando a API sobe. O app web atualiza no próximo acesso;
o app Android precisa de um APK/AAB novo só quando o código do app muda (e de `deploy/publish-apk.sh`
para atualizar o download da landing page). Mudanças na pasta `site/` também pedem `--build`.

### Usuários do banco

A API entra no Postgres como `api_user`, dona só do banco `financas`, e o agente como `agente_user`,
dono só do banco `agente`. Nenhum dos dois consegue abrir o banco do outro. O `postgres` fica para
o backup e emergências. Numa instalação nova, `infra/postgres/roles.sh` roda sozinho na primeira subida.

**Banco que já existia antes desta mudança** (feito uma vez):

```bash
cd ~/economize && git pull
# 1. Duas senhas novas no .env:
echo "API_DB_PASSWORD=$(openssl rand -hex 32)" >> .env
echo "AGENT_DB_PASSWORD=$(openssl rand -hex 32)" >> .env
# 2. O banco lê as senhas novas (reinicia só ele, alguns segundos):
docker compose -f docker-compose.prod.yml up -d db
# 3. Cria os usuários e passa a eles a posse das tabelas (não apaga nada; pode rodar de novo):
docker compose -f docker-compose.prod.yml exec db sh /docker-entrypoint-initdb.d/roles.sh
# 4. API e agente passam a usar os usuários novos:
docker compose -f docker-compose.prod.yml up -d --build api agent
docker compose -f docker-compose.prod.yml logs --tail 30 api agent
```

Para trocar uma das senhas: mude no `.env` e repita os passos 2 a 4.

**Se algo der errado**, volte API e agente para o `postgres` sem desfazer o resto. Troque no
`docker-compose.prod.yml` `api_user`/`${API_DB_PASSWORD}` e `agente_user`/`${AGENT_DB_PASSWORD}` por
`postgres`/`${POSTGRES_PASSWORD}` (ou `git checkout` da versão anterior desse arquivo) e rode
`up -d api agent`. O superusuário continua acessando tudo, então nada fica de fora.

## 8. Backups

O serviço `backup` faz um `pg_dump` dos bancos `financas` e `agente` uma vez por dia em `~/economize/backups/`
e apaga os com mais de `BACKUP_KEEP_DAYS` dias. Esses arquivos ficam no mesmo servidor, então ligue também a
**cópia externa**: o serviço `offsite` usa o [restic](https://restic.net) para enviar os backups, criptografados
no próprio servidor, para um armazenamento de fora. Guarda 14 dias, como os backups locais, porque a política
de privacidade promete que dados excluídos somem das cópias nesse prazo.

Com o Backblaze B2 (10 GB grátis):

1. Crie uma conta em backblaze.com, um bucket **privado** (ex.: `economizze-backup`) e uma *Application Key*
   com acesso só a esse bucket.
2. No `.env` do servidor:
   ```bash
   RESTIC_REPOSITORY=b2:economizze-backup:economizze
   RESTIC_PASSWORD=$(openssl rand -hex 32)   # gere e guarde também num gerenciador de senhas
   OFFSITE_KEY_ID=keyID-da-chave
   OFFSITE_KEY_SECRET=applicationKey-da-chave
   ```
3. `docker compose -f docker-compose.prod.yml up -d offsite` e confira: `docker compose -f docker-compose.prod.yml logs offsite`
   deve mostrar `backup externo ok`.

Qualquer S3 compatível também serve (`RESTIC_REPOSITORY=s3:https://endpoint/bucket/economizze`). **Sem a
`RESTIC_PASSWORD` a cópia não abre**: não a guarde só no servidor.

Para trazer uma cópia do armazenamento externo (ex.: servidor perdido), numa máquina com Docker:

```bash
docker run --rm -e RESTIC_REPOSITORY=... -e RESTIC_PASSWORD=... -e B2_ACCOUNT_ID=... -e B2_ACCOUNT_KEY=... \
  -v "$PWD/restaurado:/out" restic/restic:0.17.3 restore latest --target /out
```

**Restaurar** (apaga o que estiver no banco):

```bash
docker compose -f docker-compose.prod.yml stop api agent
docker compose -f docker-compose.prod.yml exec -T db pg_restore -U postgres -d financas --clean --if-exists < backups/financas_AAAA-MM-DD_HHMM.dump
docker compose -f docker-compose.prod.yml start api agent
```

## 9. E-mail ("esqueci minha senha")

A recuperação de senha manda um código por e-mail (RN-38). Sem SMTP configurado, o app avisa que ela ainda não
está disponível. Com o [Resend](https://resend.com) (3.000 e-mails por mês grátis):

1. Crie a conta, adicione o domínio `economizze.tech` e cadastre na Hostinger os registros DNS que o Resend
   mostrar (SPF e DKIM; sem eles os e-mails caem no spam).
2. Crie uma API key e preencha no `.env`:
   ```bash
   SMTP_HOST=smtp.resend.com
   SMTP_USERNAME=resend
   SMTP_PASSWORD=re_...
   SMTP_FROM=Economizze <nao-responda@economizze.tech>
   ```
3. `docker compose -f docker-compose.prod.yml up -d api`.

## 10. Monitoramento

- **Disponibilidade:** o workflow [`uptime.yml`](../.github/workflows/uptime.yml) confere API, agente, site e app
  a cada 15 minutos. Se algo cair, o GitHub manda e-mail (ative em *Settings → Notifications → Actions*:
  "Only notify for failed workflows"). O GitHub pausa agendamentos depois de 60 dias sem commits.
- **Erros do app:** exceções não tratadas chegam ao log da API como `Erro no app`:
  `docker compose -f docker-compose.prod.yml logs api | grep "Erro no app"`.
- **Testes:** o workflow [`ci.yml`](../.github/workflows/ci.yml) roda os testes da API, do agente e do app a cada push.

## 11. Mudar o servidor para São Paulo

A VPS atual fica em Boston: cada chamada do Brasil leva cerca de 125 ms só de ida e volta. Num datacenter em
São Paulo, cerca de 20 ms. Para migrar com poucos minutos fora do ar:

1. Contrate a nova VPS (Hostinger: escolha o datacenter "Brasil") e prepare-a como nos passos 3 e 4,
   **sem** subir ainda. Copie o `.env` antigo para ela (`scp`, de servidor para servidor).
2. Baixe o TTL do registro A do domínio para 300 segundos e espere uma hora.
3. No servidor antigo, pare a API e o agente (`docker compose -f docker-compose.prod.yml stop api agent`) e
   gere um dump de cada banco na hora:
   `docker compose -f docker-compose.prod.yml exec -T db pg_dump -U postgres -Fc financas > financas.dump`
   (e o mesmo para `agente`).
4. Copie os dumps para o servidor novo, suba só o banco (`up -d db`), restaure com `pg_restore` (seção 8),
   suba o resto (`up -d`) e troque o IP do registro A.
5. Confira o checklist abaixo e, depois de alguns dias, desligue a VPS antiga.

## Checklist antes de divulgar

- [ ] `https://SEU-DOMINIO/health/api` e `/health/agent` respondem `ok`
- [ ] Chaves de produção novas (DeepSeek, JWT, agente, senha do banco), diferentes das de desenvolvimento
- [ ] `WHATSAPP_APP_SECRET` preenchido (se o WhatsApp estiver ligado)
- [ ] Keystore do Android e `key.properties` guardados fora do PC
- [ ] Backup copiado para fora do servidor ao menos uma vez, e uma restauração testada
- [ ] Saldo no DeepSeek (é pré-pago: sem saldo, insights, chat e agente param de responder)
