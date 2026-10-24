"""RN-45: retomar uma mensagem depois de uma queda nunca registra o mesmo lançamento duas vezes."""

import os
import uuid

import pytest
from langchain_core.messages import AIMessage, HumanMessage
from langgraph.checkpoint.memory import InMemorySaver

from app.coordination import postgres_backend
from app.graph import Deps, build_graph
from app.media import MediaText
from app.service import MessageHandler
from app.whatsapp import IncomingMessage

from .fakes import FakeFinance, ScriptedLLM, tool_call

PHONE = "5511999999999"
DB_URL = os.getenv("TEST_DATABASE_URL")


class InstanceDied(BaseException):
    """Simula a instância morrendo (não é um erro que o código trataria, como um kill)."""


def handler_for(llm, finance, checkpointer, media=None, load_media=None):
    deps = Deps(llm=llm, finance=finance, media=media, load_media=load_media)
    return MessageHandler(build_graph(deps, checkpointer), finance)


def registrar(valor=45):
    return tool_call("registrar_lancamento", descricao="Almoço", valor=valor, tipo="despesa", categoria="Alimentação")


class DiesAfterWrite(FakeFinance):
    """A API grava o lançamento e a instância morre antes de o agente salvar o passo."""

    def __init__(self, **kw):
        super().__init__(**kw)
        self.die = True

    async def create_transaction(self, phone, payload, idempotency_key=None):
        tx_id = await super().create_transaction(phone, payload, idempotency_key)
        if self.die:
            self.die = False
            raise InstanceDied()
        return tx_id


class FailsOnSecondCall(ScriptedLLM):
    """O DeepSeek cai ou estoura o tempo depois de a ferramenta já ter gravado."""

    def _generate(self, messages, stop=None, run_manager=None, **kwargs):
        if not self.responses:
            raise RuntimeError("DeepSeek fora do ar")
        return super()._generate(messages, stop, run_manager, **kwargs)


async def test_queda_logo_depois_de_gravar_nao_duplica():
    finance = DiesAfterWrite(linked={PHONE: "Willian"})
    saver = InMemorySaver()
    msg = IncomingMessage(id="wamid.1", phone=PHONE, type="text", text="gastei 45 no almoço")

    a = handler_for(ScriptedLLM(responses=[registrar()], received=[]), finance, saver)
    with pytest.raises(InstanceDied):
        await a.handle(msg)
    assert len(finance.created) == 1  # a API já gravou

    # Outra instância reassume: refaz a MESMA chamada de ferramenta (mesmo id), e a API não cria outra.
    llm_b = ScriptedLLM(responses=[AIMessage(content="✅ Despesa de R$ 45,00")], received=[])
    b = handler_for(llm_b, finance, saver)
    assert await b.handle(IncomingMessage(**{**msg.__dict__, "recovered": True})) == "✅ Despesa de R$ 45,00"
    assert len(finance.created) == 1
    assert sum(isinstance(m, HumanMessage) for m in llm_b.received[0]) == 1  # a mensagem não entrou duas vezes


async def test_falha_antes_de_responder_e_mensagem_reassumida_nao_registra_de_novo():
    finance = FakeFinance(linked={PHONE: "Willian"})
    saver = InMemorySaver()
    msg = IncomingMessage(id="wamid.2", phone=PHONE, type="text", text="gastei 45 no almoço")

    a = handler_for(FailsOnSecondCall(responses=[registrar()], received=[]), finance, saver)
    assert (await a.handle(msg)).startswith("😕")
    assert len(finance.created) == 1

    llm_b = ScriptedLLM(responses=[AIMessage(content="✅ Registrado")], received=[])
    assert await handler_for(llm_b, finance, saver).handle(msg) == "✅ Registrado"
    assert len(finance.created) == 1
    assert len(llm_b.received) == 1  # só a resposta final; nenhuma ferramenta chamada de novo


async def test_resposta_pronta_e_devolvida_sem_chamar_a_ia():
    finance = FakeFinance(linked={PHONE: "Willian"})
    saver = InMemorySaver()
    msg = IncomingMessage(id="wamid.3", phone=PHONE, type="text", text="quanto gastei?")
    first = ScriptedLLM(responses=[AIMessage(content="Você gastou R$ 10")], received=[])
    assert await handler_for(first, finance, saver).handle(msg) == "Você gastou R$ 10"

    # Ex.: a resposta foi gerada, mas o envio ao WhatsApp falhou e a mensagem foi reassumida.
    no_llm = ScriptedLLM(responses=[], received=[])
    assert await handler_for(no_llm, finance, saver).handle(msg) == "Você gastou R$ 10"
    assert no_llm.received == []


async def test_queda_durante_a_transcricao_retoma_a_midia_pendente():
    finance = FakeFinance(linked={PHONE: "Willian"})
    saver = InMemorySaver()
    msg = IncomingMessage(id="wamid.4", phone=PHONE, type="audio", media_id="m1", mime="audio/ogg")

    async def load_media(_id):
        return b"", "audio/ogg"

    class DyingMedia:
        async def to_text(self, data, mime):
            raise InstanceDied()

    class Media:
        async def to_text(self, data, mime):
            return MediaText("gastei 45 no almoço")

    with pytest.raises(InstanceDied):
        await handler_for(ScriptedLLM(responses=[], received=[]), finance, saver, DyingMedia(), load_media).handle(msg)

    llm = ScriptedLLM(responses=[registrar(), AIMessage(content="✅ ok")], received=[])
    assert await handler_for(llm, finance, saver, Media(), load_media).handle(msg) == "✅ ok"
    human = [m for m in llm.received[0] if isinstance(m, HumanMessage)]
    assert len(human) == 1 and human[0].id == "wamid.4"
    assert len(finance.created) == 1


async def test_mensagens_diferentes_com_o_mesmo_valor_registram_as_duas():
    finance = FakeFinance(linked={PHONE: "Willian"})
    saver = InMemorySaver()
    llm = ScriptedLLM(responses=[registrar(), AIMessage(content="ok 1"), registrar(), AIMessage(content="ok 2")],
                      received=[])
    h = handler_for(llm, finance, saver)
    await h.handle(IncomingMessage(id="wamid.5", phone=PHONE, type="text", text="almoço 45"))
    await h.handle(IncomingMessage(id="wamid.6", phone=PHONE, type="text", text="outro almoço 45"))
    assert len(finance.created) == 2  # a proteção é por chamada, não por valor


@pytest.mark.skipif(not DB_URL, reason="defina TEST_DATABASE_URL para testar com PostgreSQL")
async def test_postgres_outra_instancia_retoma_sem_duplicar():
    phone = f"55{uuid.uuid4().int % 10**11}"
    finance = DiesAfterWrite(linked={phone: "Willian"})
    msg = IncomingMessage(id=f"wamid.{uuid.uuid4()}", phone=phone, type="text", text="gastei 45 no almoço")

    async with postgres_backend(DB_URL, 4) as (ckpt, coord):
        a = MessageHandler(build_graph(Deps(llm=ScriptedLLM(responses=[registrar()], received=[]), finance=finance,
                                            media=None, load_media=None), ckpt), finance, coord)
        with pytest.raises(InstanceDied):
            await a.handle(msg)

    async with postgres_backend(DB_URL, 4) as (ckpt, coord):  # instância nova, mesmo banco
        llm_b = ScriptedLLM(responses=[AIMessage(content="✅ ok")], received=[])
        b = MessageHandler(build_graph(Deps(llm=llm_b, finance=finance, media=None, load_media=None), ckpt),
                           finance, coord)
        assert await b.handle(msg) == "✅ ok"
    assert len(finance.created) == 1
