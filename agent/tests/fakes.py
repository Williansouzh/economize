"""Dublês para testar o grafo sem DeepSeek, WhatsApp ou backend."""

import uuid
from typing import Any

from langchain_core.language_models import BaseChatModel
from langchain_core.messages import AIMessage, BaseMessage
from langchain_core.outputs import ChatGeneration, ChatResult

from app.finance_api import BusinessContext, FinanceApiError, PlusRequired, QuotaExceeded, UserContext


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


BUSINESS = BusinessContext(
    id="p-empresa", name="Doces da Ana",
    categories=[{"id": "b1", "name": "Vendas", "type": "Income"}, {"id": "b2", "name": "DAS (imposto do MEI)", "type": "Expense"},
                {"id": "b3", "name": "Outras despesas", "type": "Expense"}],
    accounts=[{"id": "ba1", "name": "Conta da empresa"}])


class FakeFinance:
    def __init__(self, linked: dict[str, str] | None = None, codes: dict[str, str] | None = None,
                 business: bool = False, quota: int = 1000):
        self.linked = linked or {}       # phone -> nome
        self.codes = codes or {}         # código -> nome
        self.created: list[dict] = []
        self.deleted: list[str] = []
        self.business = business
        self.quota = quota
        self.profiles_used: list[str | None] = []

    async def link(self, phone, code):
        if code not in self.codes:
            raise FinanceApiError("Código inválido ou expirado. Gere um novo código no app e tente de novo.")
        self.linked[phone] = self.codes.pop(code)
        return self.linked[phone]

    def forget(self, phone):
        pass

    async def login(self, phone):
        return ("token", self.linked[phone]) if phone in self.linked else None

    async def context(self, phone):
        return UserContext(name=self.linked[phone], categories=CATEGORIES,
                           accounts=[{"id": "a1", "name": "Carteira"}, {"id": "a2", "name": "Nubank"}],
                           business=BUSINESS if self.business else None)

    async def use_quota(self, phone):
        if getattr(self, "plus", True) is False:
            raise PlusRequired("O assistente no WhatsApp faz parte do Economizze Plus. Assine no Perfil para liberar.")
        if self.quota <= 0:
            raise QuotaExceeded("Limite de mensagens do dia atingido.")
        self.quota -= 1
        return self.quota

    async def create_transaction(self, phone, payload, idempotency_key=None, profile=None):
        self.profiles_used.append(profile)
        # Igual à API (RN-45): a mesma chave devolve o lançamento já criado.
        if idempotency_key is not None:
            self.keys = getattr(self, "keys", {})
            if idempotency_key in self.keys:
                return self.keys[idempotency_key]
        self.created.append(payload)
        tx_id = f"tx{len(self.created)}"
        if idempotency_key is not None:
            self.keys[idempotency_key] = tx_id
        return tx_id

    async def transactions(self, phone, month, profile=None):
        return []

    async def delete_transaction(self, phone, tx_id, profile=None):
        self.deleted.append(tx_id)

    async def dashboard(self, phone, month, profile=None):
        return {"month": month, "totalBalance": 0, "forecastBalance": 0, "income": 0, "expenses": 0,
                "monthResult": 0, "pendingIncome": 0, "pendingExpenses": 0,
                "expensesByCategory": [], "budgets": []}
