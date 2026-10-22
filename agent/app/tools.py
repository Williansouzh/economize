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
        """
        phone = phone_of(config)
        if valor <= 0:
            return "Erro: o valor precisa ser maior que zero."
        ctx = await finance.context(phone)
        tx_type = "Expense" if tipo == "despesa" else "Income"
        cats = [c for c in ctx.categories if c["type"] == tx_type]
        cat = match_by_name(cats, categoria) or match_by_name(
            cats, "Outros" if tx_type == "Expense" else "Outras receitas") or (cats[0] if cats else None)
        acc = match_by_name(ctx.accounts, conta) or (ctx.accounts[0] if ctx.accounts else None)
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
                # Se esta chamada for reexecutada (instância caiu no meio), a API devolve o mesmo lançamento.
                "externalId": tool_call_id,
            })
        except FinanceApiError as e:
            return f"Erro ao registrar: {e}"
        return (f"OK id={tx_id} | {tipo} {brl(valor)} | categoria {cat['name']} | conta {acc['name']} "
                f"| data {when.strftime('%d/%m/%Y')} | {descricao}")

    @tool
    async def registrar_transferencia(
        valor: float,
        conta_origem: str,
        conta_destino: str,
        config: RunnableConfig,
        tool_call_id: Annotated[str, InjectedToolCallId],
        data: str | None = None,
        descricao: str = "Transferência",
    ) -> str:
        """Registra dinheiro passando de uma conta do usuário para OUTRA conta DELE (não é gasto nem receita).

        Args:
            valor: valor positivo em reais.
            conta_origem: nome da conta de onde o dinheiro sai.
            conta_destino: nome da conta para onde o dinheiro vai.
            data: data no formato AAAA-MM-DD. Omitir = hoje.
            descricao: descrição curta, ex.: "Reserva de emergência".
        """
        phone = phone_of(config)
        if valor <= 0:
            return "Erro: o valor precisa ser maior que zero."
        ctx = await finance.context(phone)
        names = ", ".join(a["name"] for a in ctx.accounts)
        origem, destino = match_by_name(ctx.accounts, conta_origem), match_by_name(ctx.accounts, conta_destino)
        if origem is None or destino is None:
            return f"Erro: não encontrei a conta de origem ou de destino. Contas do usuário: {names}."
        if origem["id"] == destino["id"]:
            return "Erro: a conta de origem e a de destino são a mesma."
        try:
            when = date.fromisoformat(data) if data else today()
        except ValueError:
            when = today()
        try:
            tx_id = await finance.create_transaction(phone, {
                "accountId": origem["id"],
                "destinationAccountId": destino["id"],
                "description": descricao.strip()[:120],
                "amount": round(valor, 2),
                "type": "Transfer",
                "date": when.isoformat(),
                "isPaid": True,
                "externalId": tool_call_id,
            })
        except FinanceApiError as e:
            return f"Erro ao registrar: {e}"
        return (f"OK id={tx_id} | transferência {brl(valor)} | de {origem['name']} para {destino['name']} "
                f"| data {when.strftime('%d/%m/%Y')}")

    @tool
    async def listar_lancamentos(config: RunnableConfig, mes: str | None = None, limite: int = 10) -> str:
        """Lista os lançamentos mais recentes (com id) de um mês. mes no formato AAAA-MM; omitir = mês atual."""
        txs = await finance.transactions(phone_of(config), month_or_current(mes))
        if not txs:
            return "Nenhum lançamento no mês."
        def line(t: dict) -> str:
            if t["type"] == "Transfer":
                return (f"id={t['id']} | {t['date']} | transferência {brl(t['amount'])} "
                        f"| {t['accountName']} → {t.get('destinationAccountName')} | {t['description']}")
            sign = "-" if t["type"] == "Expense" else "+"
            return f"id={t['id']} | {t['date']} | {sign}{brl(t['amount'])} | {t['categoryName']} | {t['description']}"

        return "\n".join(line(t) for t in txs[:limite])

    @tool
    async def excluir_lancamento(id: str, config: RunnableConfig) -> str:
        """Exclui um lançamento pelo id (use para 'desfazer' ou corrigir um registro)."""
        try:
            await finance.delete_transaction(phone_of(config), id)
        except FinanceApiError as e:
            return f"Erro ao excluir: {e}"
        return f"Lançamento {id} excluído."

    @tool
    async def resumo_do_mes(config: RunnableConfig, mes: str | None = None) -> str:
        """Resumo financeiro do mês: saldo atual e previsto, receitas, despesas, pendentes, gastos por categoria e orçamentos. mes = AAAA-MM."""
        d = await finance.dashboard(phone_of(config), month_or_current(mes))
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

    return [registrar_lancamento, registrar_transferencia, listar_lancamentos, excluir_lancamento, resumo_do_mes]
