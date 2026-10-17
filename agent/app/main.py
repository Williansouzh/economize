"""Webhook da WhatsApp Cloud API.

Rodar:  uvicorn app.main:app --host 0.0.0.0 --port 8000
URL do webhook na Meta: https://SEU-DOMINIO/webhook
"""

import logging
from contextlib import AsyncExitStack, asynccontextmanager

from fastapi import BackgroundTasks, FastAPI, HTTPException, Query, Request
from fastapi.responses import PlainTextResponse
from langchain_deepseek import ChatDeepSeek
from langgraph.checkpoint.memory import InMemorySaver

from .config import get_settings
from .coordination import InMemoryCoordinator, postgres_backend
from .finance_api import FinanceApi
from .graph import Deps, build_graph
from .media import MediaProcessor
from .service import MessageHandler
from .whatsapp import IncomingMessage, WhatsAppClient, parse_webhook, verify_signature

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s: %(message)s")
log = logging.getLogger("agent")
settings = get_settings()


@asynccontextmanager
async def lifespan(app: FastAPI):
    finance = FinanceApi(settings.finance_api_url, settings.agent_api_key)
    whatsapp = WhatsAppClient(settings.whatsapp_token, settings.whatsapp_phone_number_id, settings.graph_api_version)
    deps = Deps(
        llm=ChatDeepSeek(model=settings.deepseek_model, api_key=settings.deepseek_api_key, temperature=0.2),
        finance=finance,
        media=MediaProcessor(settings.whisper_model, settings.whisper_device,
                             settings.whisper_compute_type, settings.tesseract_lang),
        load_media=whatsapp.download_media,
        timezone=settings.timezone,
        history_limit=settings.history_limit,
    )
    async with AsyncExitStack() as stack:
        if settings.database_url:
            checkpointer, coordinator = await stack.enter_async_context(
                postgres_backend(settings.database_url, settings.database_pool_size))
        else:
            log.warning("DATABASE_URL vazio: histórico e fila ficam em memória. Rode apenas UMA instância.")
            checkpointer, coordinator = InMemorySaver(), InMemoryCoordinator()

        app.state.handler = MessageHandler(build_graph(deps, checkpointer), finance, coordinator)
        app.state.coordinator = coordinator
        app.state.whatsapp = whatsapp
        yield
    await finance.aclose()
    await whatsapp.aclose()


app = FastAPI(title="Minhas Finanças — Agente WhatsApp", lifespan=lifespan)


@app.get("/health")
async def health():
    return {"status": "ok"}


@app.get("/webhook", response_class=PlainTextResponse)
async def verify_webhook(
    mode: str = Query(alias="hub.mode"),
    token: str = Query(alias="hub.verify_token"),
    challenge: str = Query(alias="hub.challenge"),
):
    """Handshake feito pela Meta ao cadastrar o webhook."""
    if mode == "subscribe" and token == settings.whatsapp_verify_token:
        return challenge
    raise HTTPException(status_code=403)


@app.post("/webhook")
async def receive_webhook(request: Request, background: BackgroundTasks):
    body = await request.body()
    if not verify_signature(settings.whatsapp_app_secret, body, request.headers.get("X-Hub-Signature-256")):
        raise HTTPException(status_code=401, detail="Assinatura inválida")

    for msg in parse_webhook(await request.json()):
        # A Meta reenvia o webhook se demorarmos: só a primeira entrega de cada id é processada.
        if await request.app.state.coordinator.first_time(msg.id):
            background.add_task(process, request.app, msg)
    # Responde 200 na hora; o processamento (IA, Whisper, OCR) roda em segundo plano.
    return {"status": "received"}


async def process(app: FastAPI, msg: IncomingMessage):
    log.info("Mensagem %s de %s (%s)", msg.id, msg.phone, msg.type)
    reply = await app.state.handler.handle(msg)
    if reply:
        try:
            await app.state.whatsapp.send_text(msg.phone, reply)
        except Exception:
            log.exception("Falha ao enviar resposta para %s", msg.phone)
