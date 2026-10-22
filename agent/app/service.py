"""Lógica de atendimento independente de transporte (usada pelo webhook e pelo CLI)."""

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
    def __init__(self, graph, finance: FinanceApi, coordinator: Coordinator | None = None):
        self._graph = graph
        self._finance = finance
        self._coordinator = coordinator or InMemoryCoordinator()

    async def handle(self, msg: IncomingMessage) -> str | None:
        # Mensagens do mesmo usuário são processadas em ordem, uma por vez (em todas as instâncias).
        async with self._coordinator.lock(msg.phone):
            try:
                return await self._handle(msg)
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

        config = {"configurable": {"thread_id": msg.phone}}

        # Reprocessamento (a instância anterior caiu): se a mensagem já entrou no histórico,
        # não começa de novo. Continua do último passo salvo, ou só devolve a resposta pronta.
        snapshot = await self._graph.aget_state(config)
        if any(getattr(m, "id", None) == msg.id for m in snapshot.values.get("messages", [])):
            log.info("Mensagem %s já estava no histórico: retomando", msg.id)
            result = await self._graph.ainvoke(None, config) if snapshot.next else snapshot.values
            return to_whatsapp_format(result["messages"][-1].content)

        if msg.type == "text":
            state = {"messages": [HumanMessage(content=msg.text, id=msg.id)], "media": None}
        elif msg.type in MEDIA_TYPES and msg.media_id:
            state = {"messages": [], "media": {"id": msg.media_id, "mime": msg.mime, "caption": msg.text,
                                               "message_id": msg.id}}
        else:
            return "Por enquanto eu entendo *texto*, *áudio*, *imagens* e *PDFs*. 🙂"

        result = await self._graph.ainvoke(state, config)
        return to_whatsapp_format(result["messages"][-1].content)
