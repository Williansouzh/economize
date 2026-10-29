"""O webhook da Meta pode chegar repetido (a Meta reenvia se demoramos) e até duas cópias ao mesmo
tempo. Pelo endpoint de verdade, com assinatura: a mesma mensagem é processada uma vez só.
Com TEST_DATABASE_URL, roda também com o coordenador no PostgreSQL (o de produção)."""

import asyncio
import hashlib
import hmac
import json
import os
import uuid
from contextlib import asynccontextmanager

import httpx
import pytest

from app import main
from app.coordination import InMemoryCoordinator, postgres_backend

DB_URL = os.getenv("TEST_DATABASE_URL")
SECRET = "segredo-do-app"
BACKENDS = ["memoria", pytest.param("postgres", marks=pytest.mark.skipif(
    not DB_URL, reason="defina TEST_DATABASE_URL para testar com PostgreSQL"))]


@asynccontextmanager
async def coordinator(kind: str):
    if kind == "memoria":
        yield InMemoryCoordinator()
    else:
        async with postgres_backend(DB_URL, 4) as (_, coord):
            yield coord


@pytest.fixture
def processed(monkeypatch):
    """Troca o processamento (IA, Whisper, OCR) por um registro do que foi processado."""
    seen: list[str] = []

    async def spy(app, msg):
        seen.append(msg.id)

    monkeypatch.setattr(main, "process", spy)
    monkeypatch.setattr(main.settings, "whatsapp_app_secret", SECRET)
    return seen


def event(message_id: str) -> bytes:
    return json.dumps({"entry": [{"changes": [{"value": {"messages": [
        {"id": message_id, "from": "5511999990000", "type": "text", "text": {"body": "gastei 30 no almoço"}},
    ]}}]}]}).encode()


async def post(client: httpx.AsyncClient, body: bytes) -> httpx.Response:
    sig = "sha256=" + hmac.new(SECRET.encode(), body, hashlib.sha256).hexdigest()
    return await client.post("/webhook", content=body,
                             headers={"X-Hub-Signature-256": sig, "Content-Type": "application/json"})


@asynccontextmanager
async def client_with(kind: str):
    async with coordinator(kind) as coord:
        main.app.state.coordinator = coord
        transport = httpx.ASGITransport(app=main.app)  # sem lifespan: não sobe DeepSeek, Whisper nem a Meta
        async with httpx.AsyncClient(transport=transport, base_url="http://agente") as client:
            yield client


@pytest.mark.parametrize("kind", BACKENDS)
async def test_mesmo_evento_duas_vezes_processa_uma(kind, processed):
    body = event(f"wamid.{uuid.uuid4()}")
    async with client_with(kind) as client:
        first, again = await post(client, body), await post(client, body)
    # A repetição também recebe 200: senão a Meta continuaria reenviando.
    assert first.status_code == again.status_code == 200
    assert len(processed) == 1


@pytest.mark.parametrize("kind", BACKENDS)
async def test_mesmo_evento_duas_vezes_ao_mesmo_tempo_processa_uma(kind, processed):
    body = event(f"wamid.{uuid.uuid4()}")
    async with client_with(kind) as client:
        res = await asyncio.gather(*[post(client, body) for _ in range(5)])
    assert all(r.status_code == 200 for r in res)
    assert len(processed) == 1


@pytest.mark.parametrize("kind", BACKENDS)
async def test_eventos_diferentes_processam_os_dois(kind, processed):
    async with client_with(kind) as client:
        await post(client, event(f"wamid.{uuid.uuid4()}"))
        await post(client, event(f"wamid.{uuid.uuid4()}"))
    assert len(processed) == 2


async def test_evento_com_assinatura_errada_nao_e_gravado_nem_processado(processed):
    # A assinatura é conferida com o corpo bruto antes de gravar o id: um evento forjado
    # não "ocupa" o id de uma mensagem verdadeira que chegue depois.
    message_id = f"wamid.{uuid.uuid4()}"
    body = event(message_id)
    async with client_with("memoria") as client:
        forged = await client.post("/webhook", content=body, headers={"X-Hub-Signature-256": "sha256=errado"})
        real = await post(client, body)
    assert forged.status_code == 401
    assert real.status_code == 200
    assert processed == [message_id]
