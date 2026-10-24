"""Cliente HTTP do backend .NET (Financas.Api)."""

import time
from dataclasses import dataclass

import httpx


class FinanceApiError(Exception):
    pass


class QuotaExceeded(FinanceApiError):
    """Cota diária de mensagens do WhatsApp acabou (RN-48)."""


@dataclass
class BusinessContext:
    """Perfil de empresa (PJ/MEI) do usuário (RN-47): contas e categorias próprias."""
    id: str
    name: str
    categories: list[dict]
    accounts: list[dict]


@dataclass
class UserContext:
    name: str
    categories: list[dict]
    accounts: list[dict]
    business: BusinessContext | None = None


class FinanceApi:
    def __init__(self, base_url: str, agent_key: str):
        self._http = httpx.AsyncClient(base_url=base_url.rstrip("/") + "/api", timeout=30)
        self._agent_headers = {"X-Agent-Key": agent_key}
        # phone -> (token, nome, expira_em)
        self._tokens: dict[str, tuple[str, str, float]] = {}

    async def aclose(self):
        await self._http.aclose()

    @staticmethod
    def _error(res: httpx.Response) -> FinanceApiError:
        try:
            body = res.json()
            msg = body.get("error") or body.get("detail") or body.get("title")
        except ValueError:
            msg = None
        return FinanceApiError(msg or f"Erro {res.status_code} na API")

    # ---------- Rotas do agente ----------
    async def link(self, phone: str, code: str) -> str:
        res = await self._http.post("/agent/link", json={"phone": phone, "code": code}, headers=self._agent_headers)
        if res.status_code != 200:
            raise self._error(res)
        self._tokens.pop(phone, None)
        return res.json()["name"]

    def forget(self, phone: str) -> None:
        """Descarta o token em cache: o número pode ter sido desvinculado ou a conta excluída."""
        self._tokens.pop(phone, None)

    async def login(self, phone: str) -> tuple[str, str] | None:
        """Retorna (token, nome) do usuário vinculado ao número, ou None."""
        cached = self._tokens.get(phone)
        if cached and cached[2] > time.time():
            return cached[0], cached[1]
        res = await self._http.post("/agent/token", json={"phone": phone}, headers=self._agent_headers)
        if res.status_code == 404:
            return None
        if res.status_code != 200:
            raise self._error(res)
        data = res.json()
        self._tokens[phone] = (data["token"], data["name"], time.time() + 600)
        return data["token"], data["name"]

    # ---------- Rotas do usuário (com JWT) ----------
    async def _request(self, phone: str, method: str, path: str, profile: str | None = None, **kw):
        """profile: id do perfil de empresa (header X-Profile). None = perfil pessoal."""
        auth = await self.login(phone)
        if auth is None:
            raise FinanceApiError("Número não vinculado a nenhuma conta.")
        headers = {"Authorization": f"Bearer {auth[0]}", **(kw.pop("headers", None) or {})}
        if profile:
            headers["X-Profile"] = profile
        res = await self._http.request(method, path, headers=headers, **kw)
        if res.status_code >= 400:
            raise self._error(res)
        return res.json() if res.content else None

    async def context(self, phone: str) -> UserContext:
        auth = await self.login(phone)
        categories = await self._request(phone, "GET", "/categories")
        accounts = await self._request(phone, "GET", "/accounts")
        business = None
        profiles = await self._request(phone, "GET", "/profiles")
        # O agente usa o primeiro perfil de empresa; quem tem dois escolhe qual no app.
        if biz := next((p for p in profiles if p["kind"] == "Business"), None):
            business = BusinessContext(
                id=biz["id"], name=biz["name"],
                categories=await self._request(phone, "GET", "/categories", profile=biz["id"]),
                accounts=await self._request(phone, "GET", "/accounts", profile=biz["id"]))
        return UserContext(name=auth[1] if auth else "", categories=categories, accounts=accounts, business=business)

    async def use_quota(self, phone: str) -> int:
        """Gasta uma mensagem da cota diária do WhatsApp. Devolve quantas restam; sem cota, QuotaExceeded."""
        auth = await self.login(phone)
        if auth is None:
            raise FinanceApiError("Número não vinculado a nenhuma conta.")
        res = await self._http.post("/insights/quota/whatsapp", headers={"Authorization": f"Bearer {auth[0]}"})
        if res.status_code == 429:
            raise QuotaExceeded("Limite de mensagens do dia atingido.")
        if res.status_code >= 400:
            raise self._error(res)
        return res.json()["remaining"]

    async def create_transaction(self, phone: str, payload: dict, idempotency_key: str | None = None,
                                 profile: str | None = None) -> str:
        """Com idempotency_key, repetir a chamada (retomada depois de queda) devolve o mesmo lançamento (RN-45)."""
        headers = {"Idempotency-Key": idempotency_key} if idempotency_key else None
        return (await self._request(phone, "POST", "/transactions", profile, json=payload, headers=headers))["id"]

    async def transactions(self, phone: str, month: str, profile: str | None = None) -> list[dict]:
        return await self._request(phone, "GET", "/transactions", profile, params={"month": month})

    async def delete_transaction(self, phone: str, tx_id: str, profile: str | None = None) -> None:
        await self._request(phone, "DELETE", f"/transactions/{tx_id}", profile)

    async def dashboard(self, phone: str, month: str, profile: str | None = None) -> dict:
        return await self._request(phone, "GET", "/dashboard", profile, params={"month": month})
