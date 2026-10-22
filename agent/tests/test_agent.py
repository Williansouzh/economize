import hashlib
import hmac
import io
from datetime import datetime
from zoneinfo import ZoneInfo

import pytest
from langchain_core.messages import AIMessage, HumanMessage
from langgraph.checkpoint.memory import InMemorySaver
from PIL import Image, ImageDraw, ImageFont

from app.graph import Deps, build_graph, trim_history
from app.media import MediaProcessor
from app.service import MessageHandler, to_whatsapp_format
from app.tools import match_by_name
from app.whatsapp import IncomingMessage, parse_webhook, verify_signature

from .fakes import CATEGORIES, FakeFinance, ScriptedLLM, tool_call

PHONE = "5511999999999"
TODAY = datetime.now(ZoneInfo("America/Sao_Paulo")).date().isoformat()


def receipt_png() -> bytes:
    """Gera um 'print' de comprovante PIX para testar o OCR de verdade."""
    img = Image.new("RGB", (720, 520), "white")
    d = ImageDraw.Draw(img)
    font = ImageFont.load_default(size=34)
    lines = ["Comprovante de transferência", "Pix enviado", "Valor: R$ 89,90",
             "Para: Padaria Pão Quente", "Data: 15/10/2026"]
    for i, line in enumerate(lines):
        d.text((40, 40 + i * 90), line, fill="black", font=font)
    buf = io.BytesIO()
    img.save(buf, format="PNG")
    return buf.getvalue()


def make_handler(responses, finance=None, media_files=None):
    finance = finance or FakeFinance(linked={PHONE: "Willian Souza"})
    llm = ScriptedLLM(responses=responses, received=[])

    async def load_media(media_id):
        return media_files[media_id]

    deps = Deps(llm=llm, finance=finance, media=MediaProcessor(), load_media=load_media)
    return MessageHandler(build_graph(deps, InMemorySaver()), finance), finance, llm


def text(body: str) -> IncomingMessage:
    return IncomingMessage(id=body, phone=PHONE, type="text", text=body)


async def test_texto_registra_despesa_e_desfaz():
    handler, finance, llm = make_handler([
        tool_call("registrar_lancamento", descricao="Almoço", valor=45.5, tipo="despesa", categoria="alimentacao"),
        AIMessage(content="✅ Despesa de **R$ 45,50** em Alimentação"),
        tool_call("excluir_lancamento", id="tx1"),
        AIMessage(content="Pronto, apaguei."),
    ])

    reply = await handler.handle(text("gastei 45,50 no almoço"))
    assert reply == "✅ Despesa de *R$ 45,50* em Alimentação"  # markdown → WhatsApp
    call_id = llm.received[1][-1].tool_call_id  # id da chamada de ferramenta que gerou o registro
    assert finance.created == [{
        "accountId": "a1", "categoryId": "c1", "description": "Almoço", "amount": 45.5,
        "type": "Expense", "date": TODAY, "isPaid": True, "externalId": call_id,
    }]
    # O prompt de sistema traz as categorias do usuário e a data de hoje.
    system = llm.received[0][0].content
    assert "Alimentação" in system and datetime.now().strftime("%Y") in system

    # Segunda mensagem continua a mesma conversa (checkpointer por telefone).
    assert await handler.handle(text("desfazer")) == "Pronto, apaguei."
    assert finance.deleted == ["tx1"]
    history = llm.received[2]
    assert any("OK id=tx1" in str(m.content) for m in history)


async def test_print_de_comprovante_passa_por_ocr():
    handler, finance, llm = make_handler(
        [
            tool_call("registrar_lancamento", descricao="PIX para Padaria Pão Quente", valor=89.9,
                      tipo="despesa", categoria="Alimentação", data="2026-10-15", conta="nubank"),
            AIMessage(content="✅ Registrado"),
        ],
        media_files={"img1": (receipt_png(), "image/png")},
    )
    msg = IncomingMessage(id="m1", phone=PHONE, type="image", media_id="img1", mime="image/png", text="padaria")
    assert await handler.handle(msg) == "✅ Registrado"

    ocr_message = llm.received[0][-1]
    assert isinstance(ocr_message, HumanMessage)
    assert "89,90" in ocr_message.content and "Padaria" in ocr_message.content
    assert "Legenda do usuário: padaria" in ocr_message.content
    assert finance.created[0]["date"] == "2026-10-15"
    assert finance.created[0]["accountId"] == "a2"


async def test_numero_nao_vinculado_e_vinculacao():
    finance = FakeFinance(codes={"123456": "Willian Souza"})
    handler, _, _ = make_handler([], finance=finance)

    assert "VINCULAR" in await handler.handle(text("oi"))
    assert "inválido" in await handler.handle(text("vincular 999999"))
    assert (await handler.handle(text("VINCULAR 123456"))).startswith("✅ Tudo certo, Willian!")
    assert finance.linked == {PHONE: "Willian Souza"}


async def test_categoria_inexistente_cai_em_outros():
    handler, finance, _ = make_handler([
        tool_call("registrar_lancamento", descricao="Presente", valor=100, tipo="despesa", categoria="Presentes xyz"),
        AIMessage(content="ok"),
    ])
    await handler.handle(text("comprei um presente de 100"))
    assert finance.created[0]["categoryId"] == "c3"


def test_match_by_name_tolera_acento_e_erro():
    assert match_by_name(CATEGORIES, "ALIMENTACAO")["id"] == "c1"
    assert match_by_name(CATEGORIES, "transporte ")["id"] == "c2"
    assert match_by_name(CATEGORIES, "Salario")["id"] == "c4"
    assert match_by_name(CATEGORIES, "zzz") is None


def test_trim_history_comeca_em_mensagem_humana():
    msgs = [HumanMessage("a"), tool_call("x"), AIMessage("b"), HumanMessage("c"), AIMessage("d")]
    assert trim_history(msgs, 3)[0].content == "c"


def test_parse_webhook_e_assinatura():
    payload = {"entry": [{"changes": [{"value": {"messages": [
        {"id": "w1", "from": PHONE, "type": "text", "text": {"body": "oi"}},
        {"id": "w2", "from": PHONE, "type": "audio", "audio": {"id": "m9", "mime_type": "audio/ogg; codecs=opus"}},
        {"id": "w3", "from": PHONE, "type": "image", "image": {"id": "m8", "mime_type": "image/jpeg", "caption": "uber"}},
    ]}}]}]}
    msgs = parse_webhook(payload)
    assert [(m.type, m.text, m.media_id) for m in msgs] == [
        ("text", "oi", None), ("audio", "", "m9"), ("image", "uber", "m8")]

    body = b'{"a":1}'
    sig = "sha256=" + hmac.new(b"segredo", body, hashlib.sha256).hexdigest()
    assert verify_signature("segredo", body, sig)
    assert not verify_signature("segredo", body, "sha256=errado")


def test_formatacao_whatsapp():
    assert to_whatsapp_format("## Resumo\n**R$ 10**") == "Resumo\n*R$ 10*"
