"""AG-11: áudio que o Whisper não entendeu bem é confirmado com o usuário antes de virar lançamento."""

import os
from types import SimpleNamespace

import pytest
from langchain_core.messages import AIMessage
from langgraph.checkpoint.memory import InMemorySaver

from app.graph import Deps, build_graph, media_to_message
from app.media import MediaText, is_low_confidence
from app.service import MessageHandler
from app.whatsapp import IncomingMessage

from .fakes import FakeFinance, ScriptedLLM

PHONE = "5511999999999"


def seg(avg_logprob, no_speech=0.1, ratio=1.5, start=0.0, end=2.0):
    return SimpleNamespace(avg_logprob=avg_logprob, no_speech_prob=no_speech, compression_ratio=ratio,
                           start=start, end=end)


def test_criterios_de_baixa_confianca():
    assert not is_low_confidence([seg(-0.3), seg(-0.5)])
    assert is_low_confidence([seg(-0.9)])                 # modelo inseguro
    assert is_low_confidence([seg(-0.3, no_speech=0.8)])  # provavelmente não é fala
    assert is_low_confidence([seg(-0.3, ratio=3.0)])      # repetição ("iFood, iFood, iFood")
    assert is_low_confidence([])                          # nada reconhecido
    # Média ponderada pela duração: um trecho curto ruim não condena um áudio longo bom.
    assert not is_low_confidence([seg(-0.2, end=10), seg(-1.2, start=10, end=10.5)])


def test_aviso_so_aparece_quando_incerto():
    assert "baixa confiança" not in media_to_message("audio", "gastei 10", "").content
    assert "baixa confiança" in media_to_message("audio", "gastei 10", "", low_confidence=True).content


async def test_audio_incerto_vira_pergunta_e_nao_lancamento():
    class FakeMedia:
        async def to_text(self, data, mime):
            return MediaText("paguei sempre vinte reais de luz", low_confidence=True)

    async def load_media(media_id):
        return b"", "audio/ogg"

    finance = FakeFinance(linked={PHONE: "Willian"})
    llm = ScriptedLLM(responses=[AIMessage(content="Entendi R$ 120,00 de luz. Confere?")], received=[])
    deps = Deps(llm=llm, finance=finance, media=FakeMedia(), load_media=load_media)
    handler = MessageHandler(build_graph(deps, InMemorySaver()), finance)

    reply = await handler.handle(IncomingMessage(id="wamid.a", phone=PHONE, type="audio",
                                                 media_id="m1", mime="audio/ogg"))

    assert reply == "Entendi R$ 120,00 de luz. Confere?"
    system, *_, human = llm.received[0]
    assert "baixa confiança" in human.content
    assert "NÃO registre ainda" in system.content
    assert finance.created == []


@pytest.mark.skipif(not os.getenv("RUN_WHISPER_TESTS"), reason="defina RUN_WHISPER_TESTS=1 (usa o modelo real, ~20s)")
async def test_whisper_real_marca_audio_ruim(tmp_path):
    import subprocess

    from app.media import MediaProcessor

    wav, ogg = tmp_path / "a.wav", tmp_path / "a.ogg"
    subprocess.run(["espeak-ng", "-v", "pt-br", "-s", "130", "-w", str(wav), "paguei cento e vinte reais de luz"],
                   check=True)
    subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-i", str(wav), "-c:a", "libopus", str(ogg)], check=True)
    result = await MediaProcessor("small").to_text(ogg.read_bytes(), "audio/ogg")
    assert result.low_confidence  # voz sintética: o Whisper erra e sabe que está inseguro
