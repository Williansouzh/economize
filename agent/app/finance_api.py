"""Cliente HTTP do backend .NET (Financas.Api)."""

import time
from dataclasses import dataclass

import httpx


class FinanceApiError(Exception):
    pass


@dataclass
class UserContext:
    name: str
    categories: list[dict]
    accounts: list[dict]


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
    async def _request(self, phone: str, method: str, path: str, **kw):
        auth = await self.login(phone)
        if auth is None:
            raise FinanceApiError("Número não vinculado a nenhuma conta.")
        res = await self._http.request(method, path, headers={"Authorization": f"Bearer {auth[0]}"}, **kw)
        if res.status_code >= 400:
            raise self._error(res)
        return res.json() if res.content else None

    async def context(self, phone: str) -> UserContext:
        auth = await self.login(phone)
        categories = await self._request(phone, "GET", "/categories")
        accounts = await self._request(phone, "GET", "/accounts")
        return UserContext(name=auth[1] if auth else "", categories=categories, accounts=accounts)

    async def create_transaction(self, phone: str, payload: dict) -> str:
        return (await self._request(phone, "POST", "/transactions", json=payload))["id"]

    async def transactions(self, phone: str, month: str) -> list[dict]:
        return await self._request(phone, "GET", "/transactions", params={"month": month})

    async def delete_transaction(self, phone: str, tx_id: str) -> None:
        await self._request(phone, "DELETE", f"/transactions/{tx_id}")

    async def dashboard(self, phone: str, month: str) -> dict:
        return await self._request(phone, "GET", "/dashboard", params={"month": month})
