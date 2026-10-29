"""Rota interna /internal/forget (RN-30), chamada pela API."""

import httpx

from app import main
from app.whatsapp import mask_phone


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


def test_mask_phone_mostra_so_o_inicio_e_o_final_do_numero():
    assert mask_phone("5511987654321") == "5511*****4321"
    assert mask_phone("1234") == "****"


async def post_webhook(headers: dict | None = None):
    transport = httpx.ASGITransport(app=main.app)
    async with httpx.AsyncClient(transport=transport, base_url="http://agente") as client:
        return await client.post("/webhook", content=b'{"entry": []}', headers=headers or {})


async def test_webhook_sem_app_secret_recusa_tudo(monkeypatch):
    # Sem o App Secret não dá para saber se a mensagem veio da Meta: ninguém pode se passar por um número.
    monkeypatch.setattr(main.settings, "whatsapp_app_secret", "")
    monkeypatch.setattr(main.settings, "allow_unsigned_webhooks", False)
    assert (await post_webhook()).status_code == 503


async def test_webhook_com_app_secret_exige_assinatura_valida(monkeypatch):
    import hashlib
    import hmac

    monkeypatch.setattr(main.settings, "whatsapp_app_secret", "segredo")
    main.app.state.coordinator = None  # o corpo não tem mensagens: o coordenador não é chamado
    assert (await post_webhook()).status_code == 401
    assert (await post_webhook({"X-Hub-Signature-256": "sha256=errado"})).status_code == 401
    sig = "sha256=" + hmac.new(b"segredo", b'{"entry": []}', hashlib.sha256).hexdigest()
    assert (await post_webhook({"X-Hub-Signature-256": sig})).status_code == 200


async def test_webhook_sem_assinatura_so_com_a_opcao_de_desenvolvimento(monkeypatch):
    monkeypatch.setattr(main.settings, "whatsapp_app_secret", "")
    monkeypatch.setattr(main.settings, "allow_unsigned_webhooks", True)
    main.app.state.coordinator = None
    assert (await post_webhook()).status_code == 200


async def verify(token: str):
    transport = httpx.ASGITransport(app=main.app)
    async with httpx.AsyncClient(transport=transport, base_url="http://agente") as client:
        return await client.get("/webhook", params={"hub.mode": "subscribe", "hub.verify_token": token, "hub.challenge": "123"})


async def test_cadastro_do_webhook_exige_o_verify_token(monkeypatch):
    monkeypatch.setattr(main.settings, "whatsapp_verify_token", "meu-token")
    assert (await verify("errado")).status_code == 403
    res = await verify("meu-token")
    assert res.status_code == 200 and res.text == "123"


async def test_cadastro_do_webhook_sem_token_configurado_recusa(monkeypatch):
    # Antes, com o token vazio, um hub.verify_token vazio passava.
    monkeypatch.setattr(main.settings, "whatsapp_verify_token", "")
    assert (await verify("")).status_code == 403
