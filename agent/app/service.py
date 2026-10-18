"""Lógica de atendimento independente de transporte (usada pelo webhook e pelo CLI)."""

import asyncio
import logging
import re

from langchain_core.messages import HumanMessage

from .coordination import Coordinator, InMemoryCoordinator
from .finance_api import FinanceApi, FinanceApiError
from .prompts import HELP, WELCOME_UNLINKED
from .whatsapp import IncomingMessage

log = logging.getLogger(__name__)

LINK_RE = re.compile(r"^\s*vincular\s+(\d{6})\s*$", re.IGNORECASE)
MEDIA_TYPES = {"audio", "image", "document"}


def to_whatsapp_format(text: str) -> str:
    """Converte **negrito** (markdown) para *negrito* (WhatsApp)."""
    text = re.sub(r"\*\*(.+?)\*\*", r"*\1*", text)
    return re.sub(r"^#{1,6}\s*", "", text, flags=re.MULTILINE).strip()


class MessageHandler:
    def __init__(self, graph, finance: FinanceApi, coordinator: Coordinator | None = None,
                 timeout_seconds: float = 300):
        self._graph = graph
        self._finance = finance
        self._coordinator = coordinator or InMemoryCoordinator()
        self._timeout = timeout_seconds

    async def handle(self, msg: IncomingMessage) -> str | None:
        # Mensagens do mesmo usuário são processadas em ordem, uma por vez (em todas as instâncias).
        async with self._coordinator.lock(msg.phone):
            await self._coordinator.started(msg.id)
            try:
                return await asyncio.wait_for(self._handle(msg), self._timeout)
            except TimeoutError:
                log.error("Mensagem %s passou de %ss e foi abandonada", msg.id, self._timeout)
                return "😕 Demorei demais para processar isso. Pode tentar de novo?"
            except Exception:
                log.exception("Falha ao processar mensagem %s", msg.id)
                return "😕 Tive um problema para processar isso. Pode tentar de novo em instantes?"

    async def _handle(self, msg: IncomingMessage) -> str | None:
        if msg.type == "text" and (m := LINK_RE.match(msg.text)):
            try:
                name = await self._finance.link(msg.phone, m.group(1))
            except FinanceApiError as e:
                return f"❌ {e}"
            return f"✅ Tudo certo, {name.split()[0]}! Seu WhatsApp está conectado.\n\n{HELP}"

        if await self._finance.login(msg.phone) is None:
            return WELCOME_UNLINKED

        if msg.type == "text":
            state = {"messages": [HumanMessage(content=msg.text)], "media": None, "recovered": msg.recovered}
        elif msg.type in MEDIA_TYPES and msg.media_id:
            state = {"messages": [], "media": {"id": msg.media_id, "mime": msg.mime, "caption": msg.text},
                     "recovered": msg.recovered}
        else:
            return "Por enquanto eu entendo *texto*, *áudio*, *imagens* e *PDFs*. 🙂"

        result = await self._graph.ainvoke(state, {"configurable": {"thread_id": msg.phone}})
        return to_whatsapp_format(result["messages"][-1].content)
