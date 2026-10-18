"""Rota interna /internal/forget (RN-30), chamada pela API."""

import httpx

from app import main


class SpyHandler:
    def __init__(self):
        self.forgotten = []

    async def forget(self, phone):
        self.forgotten.append(phone)


async def call(key: str | None):
    transport = httpx.ASGITransport(app=main.app)  # sem lifespan: não sobe DeepSeek, Whisper nem banco
    async with httpx.AsyncClient(transport=transport, base_url="http://agente") as client:
        headers = {"X-Agent-Key": key} if key is not None else {}
        return await client.post("/internal/forget", json={"phone": "5511999990000"}, headers=headers)


async def test_forget_exige_a_chave_do_agente(monkeypatch):
    monkeypatch.setattr(main.settings, "agent_api_key", "chave-certa")
    main.app.state.handler = spy = SpyHandler()

    assert (await call(None)).status_code == 401
    assert (await call("chave-errada")).status_code == 401
    assert spy.forgotten == []

    assert (await call("chave-certa")).status_code == 204
    assert spy.forgotten == ["5511999990000"]


async def test_forget_recusa_tudo_sem_chave_configurada(monkeypatch):
    monkeypatch.setattr(main.settings, "agent_api_key", "")
    main.app.state.handler = spy = SpyHandler()
    assert (await call("")).status_code == 401
    assert spy.forgotten == []
