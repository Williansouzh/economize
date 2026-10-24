"""Grafo LangGraph do agente.

    START → ingest → agent ⇄ tools
                       ↓
                      END

- ingest: se a mensagem tem mídia (áudio/print/PDF), baixa e converte para texto (Whisper / OCR).
- agent:  DeepSeek decide o que fazer e chama ferramentas (registrar, listar, excluir, resumo).
- tools:  executa as ferramentas contra o backend .NET e devolve o resultado ao agent.

O histórico fica salvo por usuário (thread_id = telefone), então "desfazer" ou "na verdade foram 60"
funcionam como continuação da conversa.
"""

from collections.abc import Awaitable, Callable
from dataclasses import dataclass
from datetime import datetime
from typing import Any
from zoneinfo import ZoneInfo

from langchain_core.language_models import BaseChatModel
from langchain_core.messages import AnyMessage, HumanMessage, SystemMessage
from langchain_core.runnables import RunnableConfig
from langgraph.graph import END, START, MessagesState, StateGraph
from langgraph.prebuilt import ToolNode, tools_condition

from .finance_api import FinanceApi
from .media import MediaProcessor, MediaText, kind_from_mime
from .prompts import system_prompt
from .tools import make_tools

# Recebe um media_id e devolve (bytes, mime). No WhatsApp baixa da Meta; no CLI lê um arquivo local.
MediaLoader = Callable[[str], Awaitable[tuple[bytes, str]]]


class AgentState(MessagesState):
    # Mídia pendente da mensagem atual: {"id": ..., "mime": ..., "caption": ...}
    media: dict[str, Any] | None
    # A mensagem atual está sendo retomada depois de uma falha (pode já ter sido registrada).
    recovered: bool


@dataclass
class Deps:
    llm: BaseChatModel
    finance: FinanceApi
    media: MediaProcessor
    load_media: MediaLoader
    timezone: str = "America/Sao_Paulo"
    history_limit: int = 30


def trim_history(messages: list[AnyMessage], limit: int) -> list[AnyMessage]:
    """Mantém as últimas mensagens, começando sempre numa mensagem do usuário
    (cortar entre uma chamada de ferramenta e seu resultado quebra a API)."""
    recent = messages[-limit:]
    while recent and not isinstance(recent[0], HumanMessage):
        recent = recent[1:]
    return recent or messages[-1:]


def media_to_message(kind: str, text: str, caption: str, low_confidence: bool = False,
                     message_id: str | None = None) -> HumanMessage:
    if kind == "audio":
        body = f"🎤 [Áudio transcrito]\n{text or '(áudio vazio ou inaudível)'}"
        if low_confidence:
            body += ("\n⚠️ [Transcrição com baixa confiança: antes de registrar, confirme com o usuário "
                     "o valor e a descrição que você entendeu.]")
    else:
        label = "Print/imagem" if kind == "image" else "PDF"
        body = (f"🖼️ [{label} — texto extraído automaticamente, pode conter erros]\n"
                f"---\n{text or '(nenhum texto legível)'}\n---")
    if caption:
        body += f"\nLegenda do usuário: {caption}"
    # O id da mensagem do WhatsApp mostra, numa retomada, que ela já entrou no histórico.
    return HumanMessage(content=body, id=message_id)


def build_graph(deps: Deps, checkpointer=None):
    tools = make_tools(deps.finance, deps.timezone)
    llm = deps.llm.bind_tools(tools)
    tz = ZoneInfo(deps.timezone)

    async def ingest(state: AgentState) -> dict:
        media = state.get("media")
        if not media:
            return {}
        data, mime = await deps.load_media(media["id"])
        mime = mime or media.get("mime", "")
        kind = kind_from_mime(mime)
        if kind is None:
            extracted, kind = MediaText(f"(arquivo do tipo {mime} não suportado)"), "image"
        else:
            extracted = await deps.media.to_text(data, mime)
        message = media_to_message(kind, extracted.text, media.get("caption", ""), extracted.low_confidence,
                                   media.get("message_id"))
        return {"messages": [message], "media": None}

    async def agent(state: AgentState, config: RunnableConfig) -> dict:
        phone = config["configurable"]["thread_id"]
        ctx = await deps.finance.context(phone)
        prompt = SystemMessage(content=system_prompt(ctx, datetime.now(tz), recovered=state.get("recovered", False)))
        response = await llm.ainvoke([prompt, *trim_history(state["messages"], deps.history_limit)])
        return {"messages": [response]}

    graph = StateGraph(AgentState)
    graph.add_node("ingest", ingest)
    graph.add_node("agent", agent)
    graph.add_node("tools", ToolNode(tools))
    graph.add_edge(START, "ingest")
    graph.add_edge("ingest", "agent")
    graph.add_conditional_edges("agent", tools_condition, {"tools": "tools", END: END})
    graph.add_edge("tools", "agent")
    return graph.compile(checkpointer=checkpointer)
