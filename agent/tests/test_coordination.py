"""Coordenação entre instâncias. Os testes de Postgres rodam só com TEST_DATABASE_URL definido:

    TEST_DATABASE_URL=postgresql://postgres@localhost:5433/agente pytest
"""

import asyncio
import os
import uuid

import pytest
from langchain_core.messages import AIMessage

from app.coordination import InMemoryCoordinator, postgres_backend
from app.graph import Deps, build_graph
from app.media import MediaProcessor
from app.service import MessageHandler
from app.whatsapp import IncomingMessage

from .fakes import FakeFinance, ScriptedLLM, tool_call

DB_URL = os.getenv("TEST_DATABASE_URL")
needs_pg = pytest.mark.skipif(not DB_URL, reason="defina TEST_DATABASE_URL para testar com PostgreSQL")


async def assert_serializes(coord_a, coord_b, phone: str):
    """Enquanto A segura o lock do telefone, B espera; outro telefone não espera."""
    order = []
    a_inside = asyncio.Event()

    async def first():
        async with coord_a.lock(phone):
            order.append("A entrou")
            a_inside.set()
            await asyncio.sleep(0.3)
            order.append("A saiu")

    async def second():
        await a_inside.wait()
        async with coord_b.lock(phone):
            order.append("B entrou")

    async def other_phone():
        await a_inside.wait()
        async with coord_b.lock(phone + "-outro"):
            order.append("outro telefone entrou")

    await asyncio.gather(first(), second(), other_phone())
    assert order.index("outro telefone entrou") < order.index("A saiu")
    assert order.index("A saiu") < order.index("B entrou")


async def test_memoria_descarta_repetidas_e_serializa():
    coord = InMemoryCoordinator()
    assert await coord.first_time("m1") is True
    assert await coord.first_time("m1") is False
    await assert_serializes(coord, coord, "5511")


@needs_pg
async def test_postgres_duas_instancias_descartam_a_mesma_mensagem():
    msg_id = f"wamid.{uuid.uuid4()}"
    async with postgres_backend(DB_URL, 4) as (_, a), postgres_backend(DB_URL, 4) as (_, b):
        results = await asyncio.gather(*[c.first_time(msg_id) for c in (a, b, a, b)])
    assert sorted(results) == [False, False, False, True]


@needs_pg
async def test_postgres_fila_por_telefone_vale_entre_instancias():
    async with postgres_backend(DB_URL, 4) as (_, a), postgres_backend(DB_URL, 4) as (_, b):
        await assert_serializes(a, b, f"55{uuid.uuid4().int % 10**11}")


@needs_pg
async def test_postgres_historico_continua_em_outra_instancia():
    """'desfazer' processado pela instância B acha o lançamento criado pela instância A."""
    phone = f"55{uuid.uuid4().int % 10**11}"
    finance = FakeFinance(linked={phone: "Willian"})

    def handler(llm, checkpointer, coordinator):
        deps = Deps(llm=llm, finance=finance, media=MediaProcessor(), load_media=None)
        return MessageHandler(build_graph(deps, checkpointer), finance, coordinator)

    llm_a = ScriptedLLM(responses=[
        tool_call("registrar_lancamento", descricao="Almoço", valor=45, tipo="despesa", categoria="Alimentação"),
        AIMessage(content="✅ Registrado"),
    ], received=[])
    llm_b = ScriptedLLM(responses=[tool_call("excluir_lancamento", id="tx1"), AIMessage(content="Apagado")], received=[])

    async with postgres_backend(DB_URL, 4) as (ckpt_a, coord_a):
        a = handler(llm_a, ckpt_a, coord_a)
        assert await a.handle(IncomingMessage(id="1", phone=phone, type="text", text="gastei 45 no almoço")) == "✅ Registrado"

    # "Reinicia": instância nova, pools novos, mesmo banco.
    async with postgres_backend(DB_URL, 4) as (ckpt_b, coord_b):
        b = handler(llm_b, ckpt_b, coord_b)
        assert await b.handle(IncomingMessage(id="2", phone=phone, type="text", text="desfazer")) == "Apagado"

    history = llm_b.received[0]
    assert any("gastei 45" in str(m.content) for m in history)
    assert any("OK id=tx1" in str(m.content) for m in history)
    assert finance.deleted == ["tx1"]
