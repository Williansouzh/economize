# Deploy em produção

Tudo roda numa VPS com Docker: API, agente do WhatsApp, PostgreSQL, Caddy (HTTPS automático e app web)
e um serviço de backup. Só as portas 80 e 443 ficam abertas.

```
https://SEU-DOMINIO/          → app Flutter web
https://SEU-DOMINIO/api/...   → API .NET
https://SEU-DOMINIO/webhook   → agente (URL cadastrada na Meta)
https://SEU-DOMINIO/health/api, /health/agent → checagem de saúde
```

Arquivos: [`docker-compose.prod.yml`](../docker-compose.prod.yml), [`deploy/Caddyfile`](../deploy/Caddyfile),
[`deploy/web.Dockerfile`](../deploy/web.Dockerfile), [`deploy/backup.sh`](../deploy/backup.sh),
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

Abra `https://SEU-DOMINIO` no navegador: é o app web. Crie sua conta por ele.

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

A cada nova versão, aumente `version:` no `mobile/pubspec.yaml` (ex.: `1.0.1+2`; o número depois do `+`
precisa crescer sempre).

**Google Play:**

1. Crie a conta de desenvolvedor em [play.google.com/console](https://play.google.com/console) (US$ 25, uma vez).
   Contas pessoais novas precisam de um **teste fechado com 12 testadores por 14 dias** antes da produção.
2. O `applicationId` é `tech.economizze.app` (`mobile/android/app/build.gradle.kts`). Depois do primeiro
   envio à Play, ele **nunca** mais pode mudar.
3. Crie o app, envie o `.aab` em **Testes → Teste fechado** e preencha a ficha da loja.
4. A Play exige uma **política de privacidade** (URL pública) e o formulário de **Segurança dos dados**.
   O app coleta e-mail, nome e dados financeiros, e envia resumos ao DeepSeek (RN-16 em `ARQUITETURA.md`).
5. Ative a **Assinatura de apps do Google Play** (padrão): a Google guarda a chave final e a sua vira a
   "chave de upload".

## 6. WhatsApp

Com o domínio no ar, siga [`agent/README.md`](../agent/README.md#configurando-o-whatsapp-cloud-api-oficial-da-meta).
Na Meta, a URL do webhook é `https://SEU-DOMINIO/webhook`.

- Preencha `WHATSAPP_TOKEN`, `WHATSAPP_PHONE_NUMBER_ID`, `WHATSAPP_VERIFY_TOKEN` e **`WHATSAPP_APP_SECRET`**
  no `.env`. Sem o App Secret, o agente aceita webhooks que não vieram da Meta.
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
o app Android precisa de um APK/AAB novo só quando o código do app muda.

## 8. Backups

O serviço `backup` faz um `pg_dump` dos bancos `financas` e `agente` uma vez por dia em `~/economize/backups/`
e apaga os com mais de `BACKUP_KEEP_DAYS` dias. **Esses arquivos ficam no mesmo servidor**: copie para fora
regularmente, por exemplo da sua máquina:

```bash
rsync -av deploy@IP-DA-VPS:economize/backups/ ~/backups-financas/
```

**Restaurar** (apaga o que estiver no banco):

```bash
docker compose -f docker-compose.prod.yml stop api agent
docker compose -f docker-compose.prod.yml exec -T db pg_restore -U postgres -d financas --clean --if-exists < backups/financas_AAAA-MM-DD_HHMM.dump
docker compose -f docker-compose.prod.yml start api agent
```

## Checklist antes de divulgar

- [ ] `https://SEU-DOMINIO/health/api` e `/health/agent` respondem `ok`
- [ ] Chaves de produção novas (DeepSeek, JWT, agente, senha do banco), diferentes das de desenvolvimento
- [ ] `WHATSAPP_APP_SECRET` preenchido (se o WhatsApp estiver ligado)
- [ ] Keystore do Android e `key.properties` guardados fora do PC
- [ ] Backup copiado para fora do servidor ao menos uma vez, e uma restauração testada
- [ ] Saldo no DeepSeek (é pré-pago: sem saldo, insights, chat e agente param de responder)
