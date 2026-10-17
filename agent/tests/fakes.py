"""Dublês para testar o grafo sem DeepSeek, WhatsApp ou backend."""

import uuid
from typing import Any

from langchain_core.language_models import BaseChatModel
from langchain_core.messages import AIMessage, BaseMessage
from langchain_core.outputs import ChatGeneration, ChatResult

from app.finance_api import FinanceApiError, UserContext


class ScriptedLLM(BaseChatModel):
    """Devolve respostas pré-definidas, em ordem, e guarda o que recebeu."""

    responses: list[AIMessage]
    received: list[list[BaseMessage]] = []

    @property
    def _llm_type(self) -> str:
        return "scripted"

    def bind_tools(self, tools: Any, **kwargs: Any):
        return self

    def _generate(self, messages, stop=None, run_manager=None, **kwargs) -> ChatResult:
        self.received.append(list(messages))
        return ChatResult(generations=[ChatGeneration(message=self.responses.pop(0))])


def tool_call(name: str, **args) -> AIMessage:
    return AIMessage(content="", tool_calls=[{"name": name, "args": args, "id": f"call_{uuid.uuid4().hex[:8]}"}])


CATEGORIES = [
    {"id": "c1", "name": "Alimentação", "type": "Expense"},
    {"id": "c2", "name": "Transporte", "type": "Expense"},
    {"id": "c3", "name": "Outros", "type": "Expense"},
    {"id": "c4", "name": "Salário", "type": "Income"},
    {"id": "c5", "name": "Outras receitas", "type": "Income"},
]


class FakeFinance:
    def __init__(self, linked: dict[str, str] | None = None, codes: dict[str, str] | None = None):
        self.linked = linked or {}       # phone -> nome
        self.codes = codes or {}         # código -> nome
        self.created: list[dict] = []
        self.deleted: list[str] = []

    async def link(self, phone, code):
        if code not in self.codes:
            raise FinanceApiError("Código inválido ou expirado.")
        self.linked[phone] = self.codes.pop(code)
        return self.linked[phone]

    async def login(self, phone):
        return ("token", self.linked[phone]) if phone in self.linked else None

    async def context(self, phone):
        return UserContext(name=self.linked[phone], categories=CATEGORIES,
                           accounts=[{"id": "a1", "name": "Carteira"}, {"id": "a2", "name": "Nubank"}])

    async def create_transaction(self, phone, payload):
        self.created.append(payload)
        return f"tx{len(self.created)}"

    async def transactions(self, phone, month):
        return []

    async def delete_transaction(self, phone, tx_id):
        self.deleted.append(tx_id)

    async def dashboard(self, phone, month):
        return {"month": month, "totalBalance": 0, "income": 0, "expenses": 0, "monthResult": 0,
                "expensesByCategory": [], "budgets": []}
