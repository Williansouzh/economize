"""Ferramentas que o agente (DeepSeek) pode chamar. O telefone do usuário vem do thread_id do LangGraph."""

import difflib
import unicodedata
from datetime import date, datetime
from typing import Annotated, Literal
from zoneinfo import ZoneInfo

from langchain_core.runnables import RunnableConfig
from langchain_core.tools import InjectedToolCallId, tool

from .finance_api import FinanceApi, FinanceApiError


def _norm(s: str) -> str:
    return unicodedata.normalize("NFKD", s).encode("ascii", "ignore").decode().lower().strip()


def match_by_name(items: list[dict], name: str | None) -> dict | None:
    """Acha categoria/conta pelo nome tolerando acento, caixa e pequenas diferenças."""
    if not name or not items:
        return None
    target = _norm(name)
    by_name = {_norm(i["name"]): i for i in items}
    if target in by_name:
        return by_name[target]
    for key, item in by_name.items():
        if target in key or key in target:
            return item
    close = difflib.get_close_matches(target, list(by_name), n=1, cutoff=0.6)
    return by_name[close[0]] if close else None


def brl(v: float) -> str:
    return f"R$ {v:,.2f}".replace(",", "X").replace(".", ",").replace("X", ".")


def make_tools(finance: FinanceApi, timezone: str):
    tz = ZoneInfo(timezone)

    def today() -> date:
        return datetime.now(tz).date()

    def phone_of(config: RunnableConfig) -> str:
        return config["configurable"]["thread_id"]

    def month_or_current(mes: str | None) -> str:
        return mes or today().strftime("%Y-%m")

    NO_BUSINESS = "Erro: o usuário não tem perfil de empresa. Ele pode criar um no app, em Perfis."

    async def profile_of(phone: str, perfil: str) -> tuple[str | None, list[dict], list[dict]] | None:
        """(id do perfil, categorias, contas). Pessoal tem id None. Empresa sem perfil criado: None."""
        ctx = await finance.context(phone)
        if perfil != "empresa":
            return None, ctx.categories, ctx.accounts
        if ctx.business is None:
            return None
        return ctx.business.id, ctx.business.categories, ctx.business.accounts

    @tool
    async def registrar_lancamento(
        descricao: str,
        valor: float,
        tipo: Literal["despesa", "receita"],
        categoria: str,
        config: RunnableConfig,
        tool_call_id: Annotated[str, InjectedToolCallId],
        data: str | None = None,
        conta: str | None = None,
        pago: bool = True,
        perfil: Literal["pessoal", "empresa"] = "pessoal",
    ) -> str:
        """Registra UMA despesa ou receita no app de finanças.

        Args:
            descricao: descrição curta, ex.: "Mercado Extra", "Uber", "PIX para João".
            valor: valor positivo em reais, ex.: 52.9
            tipo: "despesa" ou "receita".
            categoria: nome de uma das categorias do usuário.
            data: data no formato AAAA-MM-DD. Omitir = hoje.
            conta: nome da conta. Omitir = conta padrão.
            pago: False se for uma conta a pagar/receber no futuro.
            perfil: "empresa" para o dinheiro do CNPJ/MEI (vendas, DAS, fornecedores); senão "pessoal".
        """
        phone = phone_of(config)
        if valor <= 0:
            return "Erro: o valor precisa ser maior que zero."
        scope = await profile_of(phone, perfil)
        if scope is None:
            return NO_BUSINESS
        profile_id, categories, accounts = scope
        tx_type = "Expense" if tipo == "despesa" else "Income"
        cats = [c for c in categories if c["type"] == tx_type]
        fallback = ("Outros", "Outras despesas") if tx_type == "Expense" else ("Outras receitas",)
        cat = match_by_name(cats, categoria) or next(
            (c for f in fallback if (c := match_by_name(cats, f))), None) or (cats[0] if cats else None)
        acc = match_by_name(accounts, conta) or (accounts[0] if accounts else None)
        if cat is None or acc is None:
            return "Erro: usuário não tem categorias ou contas cadastradas."

        try:
            when = date.fromisoformat(data) if data else today()
        except ValueError:
            when = today()

        try:
            tx_id = await finance.create_transaction(phone, {
                "accountId": acc["id"],
                "categoryId": cat["id"],
                "description": descricao.strip()[:120],
                "amount": round(valor, 2),
                "type": tx_type,
                "date": when.isoformat(),
                "isPaid": pago,
            # O id da chamada fica salvo no histórico: se a instância cair e a mensagem for retomada,
            # esta mesma chamada é refeita com o mesmo id e a API devolve o lançamento já criado.
            }, idempotency_key=f"wa:{tool_call_id}", profile=profile_id)
        except FinanceApiError as e:
            return f"Erro ao registrar: {e}"
        return (f"OK id={tx_id} | perfil {perfil} | {tipo} {brl(valor)} | categoria {cat['name']} | conta {acc['name']} "
                f"| data {when.strftime('%d/%m/%Y')} | {descricao}")

    @tool
    async def listar_lancamentos(config: RunnableConfig, mes: str | None = None, limite: int = 10,
                                 perfil: Literal["pessoal", "empresa"] = "pessoal") -> str:
        """Lista os lançamentos mais recentes (com id) de um mês. mes no formato AAAA-MM; omitir = mês atual."""
        scope = await profile_of(phone_of(config), perfil)
        if scope is None:
            return NO_BUSINESS
        txs = await finance.transactions(phone_of(config), month_or_current(mes), profile=scope[0])
        if not txs:
            return "Nenhum lançamento no mês."
        lines = [
            f"id={t['id']} | {t['date']} | {'-' if t['type'] == 'Expense' else '+'}{brl(t['amount'])} "
            f"| {t['categoryName']} | {t['description']}"
            for t in txs[:limite]
        ]
        return "\n".join(lines)

    @tool
    async def excluir_lancamento(id: str, config: RunnableConfig,
                                 perfil: Literal["pessoal", "empresa"] = "pessoal") -> str:
        """Exclui um lançamento pelo id (use para 'desfazer' ou corrigir um registro). Use o mesmo perfil do registro."""
        scope = await profile_of(phone_of(config), perfil)
        if scope is None:
            return NO_BUSINESS
        try:
            await finance.delete_transaction(phone_of(config), id, profile=scope[0])
        except FinanceApiError as e:
            return f"Erro ao excluir: {e}"
        return f"Lançamento {id} excluído."

    @tool
    async def resumo_do_mes(config: RunnableConfig, mes: str | None = None,
                            perfil: Literal["pessoal", "empresa"] = "pessoal") -> str:
        """Resumo financeiro do mês: saldo atual e previsto, receitas, despesas, pendentes, gastos por categoria e orçamentos. mes = AAAA-MM."""
        scope = await profile_of(phone_of(config), perfil)
        if scope is None:
            return NO_BUSINESS
        d = await finance.dashboard(phone_of(config), month_or_current(mes), profile=scope[0])
        lines = [
            f"Mês {d['month']}: saldo atual {brl(d['totalBalance'])} (só pagos até hoje), "
            f"saldo previsto no fim do mês {brl(d['forecastBalance'])}, receitas {brl(d['income'])}, "
            f"despesas {brl(d['expenses'])}, resultado {brl(d['monthResult'])}, "
            f"pendentes: a receber {brl(d['pendingIncome'])}, a pagar {brl(d['pendingExpenses'])}.",
            "Despesas por categoria: " + (", ".join(
                f"{c['name']} {brl(c['total'])} ({c['percent']}%)" for c in d["expensesByCategory"]) or "nenhuma"),
        ]
        if d["budgets"]:
            lines.append("Orçamentos: " + ", ".join(
                f"{b['categoryName']} {brl(b['spent'])} de {brl(b['limit'])}" for b in d["budgets"]))
        return "\n".join(lines)

    return [registrar_lancamento, listar_lancamentos, excluir_lancamento, resumo_do_mes]
