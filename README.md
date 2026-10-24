# Economizze 💰

App mobile simples de finanças pessoais (inspirado no Organizze) com **insights de IA via DeepSeek**.

| Camada  | Tecnologia |
|---------|------------|
| Backend | .NET 10 (ASP.NET Core Minimal APIs) + EF Core + PostgreSQL + JWT |
| Mobile  | Flutter (Provider, fl_chart, http, flutter_secure_storage) |
| IA      | DeepSeek API (`deepseek-chat`), chamada **somente pelo backend** |
| Agente WhatsApp | Python + LangGraph + DeepSeek + Whisper (áudio) + Tesseract (prints) |

📐 Arquitetura, fluxos e regras de negócio: [`docs/ARQUITETURA.md`](docs/ARQUITETURA.md)
🚀 Deploy em produção (VPS + Docker + HTTPS, APK e Google Play): [`docs/DEPLOY.md`](docs/DEPLOY.md)

## Funcionalidades

- Cadastro/login (JWT; token guardado no armazenamento seguro do aparelho)
- Contas (carteira, banco…) com saldo calculado automaticamente
- Lançamentos de receitas e despesas, agrupados por dia, com categoria, conta, data e status pago/pendente
- Categorias padrão criadas no cadastro (Alimentação, Moradia, Transporte, Salário…)
- Visão geral do mês: saldo, receitas, despesas e gráfico de pizza por categoria
- Orçamentos (limite mensal por categoria) que podem se repetir todo mês, com barra de progresso e alerta de estouro
- Transferências entre contas, que mudam os saldos sem contar como receita ou despesa
- **Onboarding completo**: idade, estado, fontes de renda, quantos trabalhos, renda e objetivo
- **Pessoa física e PJ/MEI**: perfil de empresa separado do pessoal, com categorias de MEI e o teto de faturamento do ano
- **Análise da situação** inicial e mensal, comparando a renda com a de quem tem a mesma idade no Brasil (PNAD Contínua/IBGE)
- Abertura animada com a moeda da marca, números do Início que sobem até o valor e ícone do app que muda com o mês (opcional)
- **Insights IA**: nota de saúde financeira, resumo do mês, alertas, dicas e economia potencial, em tom de conversa e curtos
- **Cota da IA**: 20 perguntas por dia no chat, para não gastar todos os tokens
- **Pergunte à IA**: chat livre sobre suas finanças, com o contexto do mês
- **Assistente no WhatsApp**: mande texto, áudio, print ou PDF de comprovante e o lançamento é criado
  automaticamente (veja [`agent/README.md`](agent/README.md))

## Estrutura

```
backend/Financas.Api/
  Models/Entities.cs          # User, Account, Category, Transaction, Budget
  Data/AppDbContext.cs        # EF Core + categorias padrão
  Services/DeepSeekClient.cs  # cliente HTTP da API do DeepSeek
  Services/InsightsService.cs # monta o resumo financeiro e os prompts
  Services/FinanceService.cs  # saldos, totais por categoria, orçamentos
  Endpoints/                  # /api/auth, /api/dashboard, /api/transactions, /api/insights...
agent/app/                    # agente WhatsApp (LangGraph)
  graph.py                    # grafo: ingest → agent ⇄ tools
  tools.py                    # registrar/listar/excluir lançamentos, resumo do mês
  media.py                    # Whisper (áudio), Tesseract (imagem), pypdf (PDF)
  main.py                     # webhook da WhatsApp Cloud API
mobile/lib/
  config.dart                 # URL do backend
  services/api_client.dart    # chamadas HTTP
  state/app_state.dart        # sessão, mês selecionado, contas/categorias
  screens/                    # login, visão geral, lançamentos, IA, orçamentos
```

## Como rodar

### 1. Backend

Pré-requisitos: [.NET 10 SDK](https://dotnet.microsoft.com/download) e um PostgreSQL 16.
O jeito mais rápido de ter o banco em desenvolvimento:

```bash
docker run -d --name financas-db -e POSTGRES_PASSWORD=postgres -e POSTGRES_DB=financas -p 5432:5432 postgres:16
```

Esse é o banco que `appsettings.Development.json` já espera
(`Host=localhost;Port=5432;Database=financas;Username=postgres;Password=postgres`).
Para usar outro, defina `ConnectionStrings__Default`.

```bash
cd backend/Financas.Api

# Chave do DeepSeek (crie em https://platform.deepseek.com/api_keys)
dotnet user-secrets set "DeepSeek:ApiKey" "sk-..."

dotnet run
```

Em desenvolvimento a API usa uma chave JWT própria de `appsettings.Development.json`.
**Fora de Development ela não sobe** sem uma chave sua de pelo menos 32 caracteres
(`Jwt__Key` como variável de ambiente, ou `dotnet user-secrets set "Jwt:Key" "..."`).

A API sobe em `http://0.0.0.0:5000` e aplica as migrations do EF Core na subida (cria as tabelas num banco vazio).
Health check: `http://localhost:5000/health`.

**Migrations:** depois de mudar o modelo, gere uma nova com
`dotnet ef migrations add NomeDaMudanca -o Data/Migrations` (instale a ferramenta com `dotnet tool install -g dotnet-ef`).
Para aplicar pelo pipeline de deploy em vez de na subida, use `Database__MigrateOnStartup=false` e `dotnet ef database update`.

**Testes de integração da API:** `cd backend && dotnet test`. Cada teste cria e apaga um banco temporário;
o servidor vem de `TEST_DATABASE_URL` (padrão: `Host=localhost;Port=5432;Username=postgres;Password=postgres`).
Documentação OpenAPI: `http://localhost:5000/openapi/v1.json`.

> Em produção use variáveis de ambiente: `DeepSeek__ApiKey`, `Jwt__Key`, `ConnectionStrings__Default`.

### 2. App Flutter

Pré-requisito: [Flutter SDK](https://docs.flutter.dev/get-started/install).

```bash
cd mobile
flutter pub get

# Emulador Android (o padrão já aponta para http://10.0.2.2:5000)
flutter run

# Celular físico na mesma rede Wi-Fi: use o IP do seu PC
flutter run --dart-define=API_URL=http://192.168.0.10:5000
```

**No navegador:**

```bash
flutter run -d chrome --web-port 8080 --dart-define=API_URL=http://localhost:5000
```

A API só aceita chamadas de origens web liberadas no CORS. Suba o backend com
`Cors__AllowedOrigins__0=http://localhost:8080 dotnet run` (no Docker, `CORS_ORIGIN` no `.env`).
Para publicar: `flutter build web --dart-define=API_URL=https://api.seudominio.com.br` gera `build/web/`.

### 3. Agente do WhatsApp

Veja o passo a passo em [`agent/README.md`](agent/README.md).

### Tudo com Docker

```bash
cp .env.example .env   # preencha as chaves
docker compose up --build
```

Esse `docker-compose.yml` é para desenvolvimento. Para produção use o `docker-compose.prod.yml`
(HTTPS, app web e backups), descrito em [`docs/DEPLOY.md`](docs/DEPLOY.md).

## Endpoints principais

| Método | Rota | Descrição |
|--------|------|-----------|
| POST | `/api/auth/register` · `/api/auth/login` | Autenticação |
| GET | `/api/dashboard?month=2026-10` | Resumo do mês |
| GET/POST/PUT/DELETE | `/api/transactions` | Lançamentos |
| GET/POST/PUT/DELETE | `/api/accounts` | Contas |
| GET/POST/DELETE | `/api/categories` | Categorias |
| GET/POST/DELETE | `/api/budgets` | Orçamentos por categoria, com repetição mensal (`DELETE ?month=` para de repetir) |
| GET/POST/PUT/DELETE | `/api/transfers` | Transferências entre contas |
| POST | `/api/insights` | Análise do mês pela IA (JSON estruturado) |
| POST | `/api/insights/chat` | Pergunta livre para a IA (20 por dia) |
| GET | `/api/insights/quota` | Perguntas que restam hoje |
| GET · PUT | `/api/me/about` | Questionário (idade, UF, fontes de renda, trabalhos, renda, objetivo) |
| GET | `/api/analysis/initial` · `/api/analysis/monthly?month=` · `/api/analysis/mei` | Análises da situação e teto do MEI |
| GET · POST · PUT · DELETE | `/api/profiles` | Perfis de empresa (PJ/MEI). Header `X-Profile` escolhe o perfil nas demais rotas |
| GET · DELETE | `/api/me` | Perfil; excluir a conta e todos os dados (pede a senha) |
| POST · DELETE | `/api/me/whatsapp-code` · `/api/me/whatsapp` | Vinculação do WhatsApp |
| POST | `/api/agent/link` · `/api/agent/token` | Usadas só pelo agente (header `X-Agent-Key`) |

## Como funciona a IA

1. O app chama `POST /api/insights` com o mês.
2. O backend monta um resumo **sem dados pessoais** (totais, gastos por categoria vs. mês anterior,
   orçamentos e as 10 maiores despesas) e envia ao DeepSeek pedindo um JSON
   (`response_format: json_object`).
3. O app mostra nota de saúde financeira, resumo, alertas e dicas.

A chave do DeepSeek fica **apenas no servidor**, nunca no app.

## Próximos passos sugeridos

- Cartões de crédito e faturas
- Lançamentos recorrentes / parcelados
- Importação de extrato (OFX/CSV) com categorização automática pela IA
- Notificações quando um orçamento passar de 80%
