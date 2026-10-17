# Minhas Finanças 💰

App mobile simples de finanças pessoais (inspirado no Organizze) com **insights de IA via DeepSeek**.

| Camada  | Tecnologia |
|---------|------------|
| Backend | .NET 10 (ASP.NET Core Minimal APIs) + EF Core + SQLite + JWT |
| Mobile  | Flutter (Provider, fl_chart, http, flutter_secure_storage) |
| IA      | DeepSeek API (`deepseek-chat`), chamada **somente pelo backend** |
| Agente WhatsApp | Python + LangGraph + DeepSeek + Whisper (áudio) + Tesseract (prints) |

📐 Arquitetura, fluxos e regras de negócio: [`docs/ARQUITETURA.md`](docs/ARQUITETURA.md)

## Funcionalidades

- Cadastro/login (JWT; token guardado no armazenamento seguro do aparelho)
- Contas (carteira, banco…) com saldo calculado automaticamente
- Lançamentos de receitas e despesas, agrupados por dia, com categoria, conta, data e status pago/pendente
- Categorias padrão criadas no cadastro (Alimentação, Moradia, Transporte, Salário…)
- Visão geral do mês: saldo, receitas, despesas e gráfico de pizza por categoria
- Orçamentos (limite mensal por categoria) com barra de progresso e alerta de estouro
- **Insights IA**: nota de saúde financeira, resumo do mês, alertas, dicas e economia potencial
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

Pré-requisito: [.NET 10 SDK](https://dotnet.microsoft.com/download).

```bash
cd backend/Financas.Api

# Chave do DeepSeek (crie em https://platform.deepseek.com/api_keys)
dotnet user-secrets set "DeepSeek:ApiKey" "sk-..."

dotnet run
```

Em desenvolvimento a API usa uma chave JWT própria de `appsettings.Development.json`.
**Fora de Development ela não sobe** sem uma chave sua de pelo menos 32 caracteres
(`Jwt__Key` como variável de ambiente, ou `dotnet user-secrets set "Jwt:Key" "..."`).

Testes de integração da API: `cd backend && dotnet test`.

A API sobe em `http://0.0.0.0:5000` e cria o banco `financas.db` automaticamente.
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

### 3. Agente do WhatsApp

Veja o passo a passo em [`agent/README.md`](agent/README.md).

### Tudo com Docker

```bash
cp .env.example .env   # preencha as chaves
docker compose up --build
```

## Endpoints principais

| Método | Rota | Descrição |
|--------|------|-----------|
| POST | `/api/auth/register` · `/api/auth/login` | Autenticação |
| GET | `/api/dashboard?month=2026-10` | Resumo do mês |
| GET/POST/PUT/DELETE | `/api/transactions` | Lançamentos |
| GET/POST/PUT/DELETE | `/api/accounts` | Contas |
| GET/POST/DELETE | `/api/categories` | Categorias |
| GET/POST/DELETE | `/api/budgets` | Orçamentos por categoria |
| POST | `/api/insights` | Análise do mês pela IA (JSON estruturado) |
| POST | `/api/insights/chat` | Pergunta livre para a IA |
| GET · POST · DELETE | `/api/me` · `/api/me/whatsapp-code` · `/api/me/whatsapp` | Perfil e vinculação do WhatsApp |
| POST | `/api/agent/link` · `/api/agent/token` | Usadas só pelo agente (header `X-Agent-Key`) |

## Como funciona a IA

1. O app chama `POST /api/insights` com o mês.
2. O backend monta um resumo **sem dados pessoais** (totais, gastos por categoria vs. mês anterior,
   orçamentos e as 10 maiores despesas) e envia ao DeepSeek pedindo um JSON
   (`response_format: json_object`).
3. O app mostra nota de saúde financeira, resumo, alertas e dicas.

A chave do DeepSeek fica **apenas no servidor**, nunca no app.

## Próximos passos sugeridos

- Migrations do EF Core (`dotnet ef migrations add Initial`) e PostgreSQL em produção
- Cartões de crédito e faturas
- Lançamentos recorrentes / parcelados
- Transferência entre contas
- Importação de extrato (OFX/CSV) com categorização automática pela IA
- Notificações quando um orçamento passar de 80%
