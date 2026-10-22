import asyncio
import os
import uuid
from types import SimpleNamespace

import pytest
from langchain_core.messages import AIMessage, HumanMessage
from langgraph.checkpoint.memory import InMemorySaver

from app.coordination import postgres_backend
from app.graph import Deps, build_graph, media_to_message
from app.media import MediaText, is_low_confidence
from app.prompts import system_prompt
from app.service import MessageHandler
from app.whatsapp import IncomingMessage

from .fakes import FakeFinance, ScriptedLLM, tool_call

PHONE = "5511999999999"
DB_URL = os.getenv("TEST_DATABASE_URL")


def handler_for(llm, finance, checkpointer, media=None):
    deps = Deps(llm=llm, finance=finance, media=media, load_media=lambda _id: None)
    return MessageHandler(build_graph(deps, checkpointer), finance)


def text(body: str, msg_id: str = "wamid.1") -> IncomingMessage:
    return IncomingMessage(id=msg_id, phone=PHONE, type="text", text=body)


# ---------- Transferência entre contas ----------

async def test_transferencia_vai_para_a_api_sem_categoria_e_com_destino():
    finance = FakeFinance(linked={PHONE: "Willian"})
    llm = ScriptedLLM(responses=[
        tool_call("registrar_transferencia", valor=500, conta_origem="nubank", conta_destino="Carteira"),
        AIMessage(content="✅ Transferi"),
    ], received=[])
    h = handler_for(llm, finance, InMemorySaver())

    assert await h.handle(text("passei 500 do nubank pra carteira")) == "✅ Transferi"
    payload = finance.created[0]
    assert payload["type"] == "Transfer"
    assert (payload["accountId"], payload["destinationAccountId"]) == ("a2", "a1")
    assert "categoryId" not in payload
    assert payload["externalId"].startswith("call_")


async def test_transferencia_com_conta_desconhecida_ou_igual_devolve_erro_ao_modelo():
    finance = FakeFinance(linked={PHONE: "Willian"})
    llm = ScriptedLLM(responses=[
        tool_call("registrar_transferencia", valor=50, conta_origem="Inter", conta_destino="Carteira"),
        tool_call("registrar_transferencia", valor=50, conta_origem="Carteira", conta_destino="carteira"),
        AIMessage(content="ok"),
    ], received=[])
    await handler_for(llm, finance, InMemorySaver()).handle(text("transfere 50 do inter"))

    results = [m.content for m in llm.received[-1] if m.type == "tool"]
    assert "não encontrei a conta" in results[0] and "Carteira, Nubank" in results[0]
    assert "mesma" in results[1]
    assert finance.created == []


def test_prompt_separa_transferencia_de_pix_para_outra_pessoa():
    from app.finance_api import UserContext
    from datetime import datetime
    p = system_prompt(UserContext("W", [], [{"name": "Carteira"}]), datetime(2026, 10, 22))
    assert "registrar_transferencia" in p and "OUTRA pessoa continua sendo despesa" in p


# ---------- Reprocessamento depois de queda ----------

class CrashingLLM(ScriptedLLM):
    """Responde o roteiro e depois 'cai', como uma instância que morreu no meio."""

    def _generate(self, messages, stop=None, run_manager=None, **kwargs):
        if not self.responses:
            raise RuntimeError("instância caiu")
        return super()._generate(messages, stop, run_manager, **kwargs)


async def test_mensagem_retomada_nao_repete_o_lancamento():
    finance = FakeFinance(linked={PHONE: "Willian"})
    saver = InMemorySaver()  # num deploy real é o PostgreSQL, compartilhado entre instâncias
    msg = text("gastei 45 no almoço", "wamid.crash")

    # Instância A registra o lançamento e cai antes de responder.
    a = handler_for(CrashingLLM(responses=[
        tool_call("registrar_lancamento", descricao="Almoço", valor=45, tipo="despesa", categoria="Alimentação"),
    ], received=[]), finance, saver)
    assert (await a.handle(msg)).startswith("😕")
    assert len(finance.created) == 1

    # Instância B reassume a mesma mensagem: continua do passo salvo, sem registrar de novo.
    llm_b = ScriptedLLM(responses=[AIMessage(content="✅ Despesa de R$ 45,00")], received=[])
    b = handler_for(llm_b, finance, saver)
    assert await b.handle(msg) == "✅ Despesa de R$ 45,00"
    assert len(finance.created) == 1
    assert sum(isinstance(m, HumanMessage) for m in llm_b.received[0]) == 1  # a mensagem não foi duplicada


async def test_resposta_pronta_e_reenviada_sem_chamar_a_ia_de_novo():
    finance = FakeFinance(linked={PHONE: "Willian"})
    saver = InMemorySaver()
    msg = text("oi, quanto gastei?", "wamid.pronta")
    first = handler_for(ScriptedLLM(responses=[AIMessage(content="Você gastou R$ 10")], received=[]), finance, saver)
    assert await first.handle(msg) == "Você gastou R$ 10"

    # Ex.: a resposta foi gerada mas o envio ao WhatsApp falhou. Reprocessar só reenvia.
    no_llm = ScriptedLLM(responses=[], received=[])
    assert await handler_for(no_llm, finance, saver).handle(msg) == "Você gastou R$ 10"
    assert no_llm.received == []


# ---------- Áudio com baixa confiança ----------

def seg(avg_logprob, no_speech=0.1, ratio=1.5, start=0.0, end=2.0):
    return SimpleNamespace(avg_logprob=avg_logprob, no_speech_prob=no_speech, compression_ratio=ratio, start=start, end=end)


def test_criterios_de_baixa_confianca():
    assert not is_low_confidence([seg(-0.3), seg(-0.5)])
    assert is_low_confidence([seg(-0.9)])                 # modelo inseguro
    assert is_low_confidence([seg(-0.3, no_speech=0.8)])  # provavelmente não é fala
    assert is_low_confidence([seg(-0.3, ratio=3.0)])      # repetição ("iFood, iFood, iFood")
    assert is_low_confidence([])                          # nada reconhecido
    # Média ponderada pela duração: um trecho curto ruim não condena um áudio longo bom.
    assert not is_low_confidence([seg(-0.2, end=10), seg(-1.2, start=10, end=10.5)])


async def test_audio_incerto_chega_ao_modelo_com_aviso_para_confirmar():
    class FakeMedia:
        async def to_text(self, data, mime):
            return MediaText("paguei sempre vinte reais de luz", low_confidence=True)

    finance = FakeFinance(linked={PHONE: "Willian"})
    llm = ScriptedLLM(responses=[AIMessage(content="Entendi R$ 120,00 de luz. Confere?")], received=[])
    deps = Deps(llm=llm, finance=finance, media=FakeMedia(), load_media=lambda _id: asyncio.sleep(0, (b"", "audio/ogg")))
    h = MessageHandler(build_graph(deps, InMemorySaver()), finance)

    reply = await h.handle(IncomingMessage(id="wamid.a", phone=PHONE, type="audio", media_id="m1", mime="audio/ogg"))
    assert reply == "Entendi R$ 120,00 de luz. Confere?"
    human = llm.received[0][-1]
    assert "baixa confiança" in human.content and human.id == "wamid.a"
    assert "NÃO registre ainda" in llm.received[0][0].content  # regra no prompt de sistema
    assert finance.created == []


def test_aviso_so_aparece_quando_incerto():
    assert "baixa confiança" not in media_to_message("audio", "gastei 10", "").content
    assert "baixa confiança" in media_to_message("audio", "gastei 10", "", low_confidence=True).content


@pytest.mark.skipif(not os.getenv("RUN_WHISPER_TESTS"), reason="defina RUN_WHISPER_TESTS=1 (baixa o modelo, ~20s)")
async def test_whisper_real_marca_audio_ruim(tmp_path):
    import subprocess
    from app.media import MediaProcessor
    wav, ogg = tmp_path / "a.wav", tmp_path / "a.ogg"
    subprocess.run(["espeak-ng", "-v", "pt-br", "-s", "130", "-w", str(wav), "paguei cento e vinte reais de luz"], check=True)
    subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-i", str(wav), "-c:a", "libopus", str(ogg)], check=True)
    result = await MediaProcessor("small").to_text(ogg.read_bytes(), "audio/ogg")
    assert result.low_confidence  # voz sintética: o Whisper erra e sabe que está inseguro


# ---------- Mensagens presas (PostgreSQL) ----------

@pytest.mark.skipif(not DB_URL, reason="defina TEST_DATABASE_URL para testar com PostgreSQL")
async def test_postgres_reassume_mensagem_presa_e_desiste_depois_de_3_tentativas():
    msg_id = f"wamid.{uuid.uuid4()}"
    payload = {"id": msg_id, "phone": PHONE, "type": "text", "text": "oi", "media_id": None, "mime": ""}
    async with postgres_backend(DB_URL, 4, processing_timeout_s=1) as (_, a), \
               postgres_backend(DB_URL, 4, processing_timeout_s=1) as (_, b):
        # O banco de teste é compartilhado: olha só as mensagens deste teste.
        mine = lambda rows: [r for r in rows if r["id"] == msg_id]
        assert await a.claim(msg_id, payload)
        assert mine(await b.reclaim_stale()) == []     # ainda dentro do prazo

        await asyncio.sleep(1.2)                       # "instância A caiu"
        got = await asyncio.gather(a.reclaim_stale(), b.reclaim_stale())
        assert sum(len(mine(r)) for r in got) == 1     # só uma instância reassume (2ª tentativa)
        assert mine(await b.reclaim_stale()) == []     # prazo recomeçou

        await asyncio.sleep(1.2)
        assert len(mine(await b.reclaim_stale())) == 1  # 3ª tentativa
        await asyncio.sleep(1.2)
        assert mine(await b.reclaim_stale()) == []      # esgotou: vira "failed"

        done_id = f"wamid.{uuid.uuid4()}"
        await a.claim(done_id, {**payload, "id": done_id})
        await a.done(done_id)
        await asyncio.sleep(1.2)
        assert [r for r in await b.reclaim_stale() if r["id"] == done_id] == []  # concluída não volta
