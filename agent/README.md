# Agente WhatsApp (LangGraph + DeepSeek)

Registre lançamentos mandando **texto, áudio, print ou PDF** para um número de WhatsApp.
O agente entende a mensagem, escolhe a categoria e grava a transação no backend .NET.

```
WhatsApp ──webhook──▶ FastAPI (/webhook)
                         │
                         ▼
              ┌──────── LangGraph ────────┐
              │ ingest → agent ⇄ tools    │
              │   │        │       │      │
              │ Whisper  DeepSeek  API    │
              │ Tesseract          .NET   │
              └───────────────────────────┘
                         │
WhatsApp ◀──resposta─────┘
```

| Nó | O que faz |
|----|-----------|
| `ingest` | Baixa a mídia e converte em texto: **áudio** com Whisper (local), **imagem** com Tesseract OCR e **PDF** com pypdf. O DeepSeek só entende texto. |
| `agent`  | DeepSeek (`deepseek-chat`, com function calling) decide o que fazer. O prompt traz as categorias e contas do usuário e a data de hoje. |
| `tools`  | `registrar_lancamento`, `listar_lancamentos`, `excluir_lancamento` e `resumo_do_mes` chamam o backend .NET. |

O histórico é guardado por telefone (`thread_id`), então dá para continuar a conversa:
_"desfazer"_, _"na verdade foram 60"_, _"quanto gastei com comida?"_.

### Exemplos

| Você manda | O agente faz |
|---|---|
| `gastei 45 no almoço` | Despesa de R$ 45,00 em Alimentação, com a data de hoje |
| 🎤 _"recebi dois mil do freela ontem"_ | Receita de R$ 2.000,00 em Freelance, com a data de ontem |
| 🖼️ print de comprovante PIX | Despesa com o valor, a data e o favorecido do comprovante |
| 🖼️ print da fatura com 5 compras | 5 lançamentos, um para cada compra |
| `desfazer` | Exclui o último lançamento registrado |
| `quanto gastei esse mês?` | Resumo com o total por categoria |

## Vinculação do número

1. No app: ⋮ → **Conectar WhatsApp** → **Gerar código**.
2. Mande `VINCULAR 123456` para o número do assistente.
3. O agente chama `POST /api/agent/link` e o número fica ligado à sua conta.

Assim só o dono do número consegue vinculá-lo. O agente se autentica no backend com o header
`X-Agent-Key`, troca o telefone por um JWT do usuário (`/api/agent/token`) e então usa as rotas normais da API.

## Rodando localmente

```bash
# 1) Backend (em outro terminal; precisa de um PostgreSQL, veja o README principal)
cd backend/Financas.Api
dotnet user-secrets set "Agent:ApiKey" "minha-chave-do-agente"
dotnet run

# 2) Agente
cd agent
python -m venv .venv && source .venv/bin/activate
pip install -r requirements-dev.txt
sudo apt install tesseract-ocr tesseract-ocr-por   # macOS: brew install tesseract tesseract-lang
cp .env.example .env                               # preencha DEEPSEEK_API_KEY e AGENT_API_KEY

# Testar pelo terminal, sem WhatsApp:
python -m app.cli --phone 5511999999999
#   você> VINCULAR 123456          (código gerado no app)
#   você> gastei 32 no uber
#   você> /audio ~/audio.ogg
#   você> /imagem ~/comprovante.png

# Servidor do webhook:
uvicorn app.main:app --port 8000

# Testes (sem precisar de DeepSeek: usam um LLM roteirizado)
pytest
```

## Configurando o WhatsApp (Cloud API oficial da Meta)

1. Acesse <https://developers.facebook.com/apps>, clique em **Criar app** (tipo *Business*) e adicione o produto **WhatsApp**.
2. Em **WhatsApp → Configuração da API**:
   - copie o **token de acesso temporário** para `WHATSAPP_TOKEN` (ele dura 24h; para produção, gere um token permanente com um *Usuário do sistema* no Business Manager);
   - copie o **Phone number ID** para `WHATSAPP_PHONE_NUMBER_ID`;
   - em modo de teste, adicione o seu celular como destinatário.
3. Exponha o agente com HTTPS. Em desenvolvimento: `ngrok http 8000` ou `cloudflared tunnel --url http://localhost:8000`.
4. Em **WhatsApp → Configuração → Webhook**:
   - URL de callback: `https://SEU-ENDERECO/webhook`
   - Token de verificação: o mesmo valor de `WHATSAPP_VERIFY_TOKEN`
   - Assine o campo **messages**.
5. Em **Configurações do app → Básico**, copie a **Chave secreta do app** para `WHATSAPP_APP_SECRET`.
   Com ela, o agente rejeita webhooks que não vierem da Meta.

> Mensagens que o usuário inicia abrem uma janela de atendimento de 24h, gratuita na Cloud API.
> O bot só responde, então não precisa de templates.

## Observações

- **Áudio incerto:** quando o Whisper não tem segurança (voz ruim, barulho), a transcrição chega ao modelo
  marcada e ele confirma o valor com você antes de registrar (AG-11). Para rodar o teste com o modelo real:
  `RUN_WHISPER_TESTS=1 pytest tests/test_audio_confianca.py`.
- **Whisper:** `WHISPER_MODEL=small` é um bom equilíbrio em CPU (~500 MB, alguns segundos por áudio).
  Use `base` em servidores fracos ou `medium` para mais precisão. O modelo é baixado no primeiro áudio.
- **Histórico e várias instâncias:** sem `DATABASE_URL`, o histórico das conversas, os ids de mensagens
  já vistas e a fila por telefone ficam na memória do processo. Isso serve para desenvolvimento, mas
  reiniciar apaga as conversas e só pode existir **uma** instância.
  Com `DATABASE_URL` apontando para um PostgreSQL:
  - o histórico usa o checkpointer oficial do LangGraph (`langgraph-checkpoint-postgres`) e sobrevive a reinícios;
  - cada id de mensagem da Meta é gravado numa tabela com chave única, então um reenvio é descartado mesmo que caia em outra instância;
  - mensagens do mesmo telefone são processadas uma de cada vez com `pg_advisory_lock`, que o Postgres libera sozinho se a instância cair.

  O `docker-compose.yml` já sobe o Postgres e configura isso. Para testar com Postgres:
  `TEST_DATABASE_URL=postgresql://... pytest`.
- **Segurança:** textos de OCR e áudio são tratados como dado, e o prompt manda ignorar instruções contidas neles.
  Além disso, as ferramentas só agem na conta do próprio remetente.
