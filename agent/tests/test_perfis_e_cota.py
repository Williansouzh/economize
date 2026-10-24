"""RN-47 (perfil de empresa no WhatsApp) e RN-48 (cota diária de mensagens)."""

from langchain_core.messages import AIMessage

from .fakes import FakeFinance
from .test_agent import PHONE, make_handler, text, tool_call


async def test_lancamento_da_empresa_vai_para_o_perfil_de_empresa():
    finance = FakeFinance(linked={PHONE: "Ana Souza"}, business=True)
    handler, finance, llm = make_handler([
        tool_call("registrar_lancamento", descricao="Bolo de pote", valor=120, tipo="receita",
                  categoria="vendas", perfil="empresa"),
        AIMessage(content="✅ *R$ 120,00* em Vendas, na empresa."),
        tool_call("registrar_lancamento", descricao="Mercado", valor=80, tipo="despesa", categoria="alimentacao"),
        AIMessage(content="✅ *R$ 80,00* no Mercado."),
    ], finance=finance)

    await handler.handle(text("vendi 120 de bolo de pote"))
    await handler.handle(text("gastei 80 no mercado"))

    assert finance.profiles_used == ["p-empresa", None]
    assert finance.created[0]["categoryId"] == "b1" and finance.created[0]["accountId"] == "ba1"
    assert finance.created[1]["accountId"] == "a1"
    prompt = llm.received[0][0].content
    assert "Doces da Ana" in prompt and "DAS (imposto do MEI)" in prompt


async def test_sem_perfil_de_empresa_o_agente_avisa_em_vez_de_lancar_no_pessoal():
    handler, finance, llm = make_handler([
        tool_call("registrar_lancamento", descricao="Venda", valor=50, tipo="receita", categoria="vendas", perfil="empresa"),
        AIMessage(content="Você ainda não tem perfil de empresa. Dá para criar no app."),
    ])
    await handler.handle(text("vendi 50 na empresa"))
    assert finance.created == []
    assert "não tem perfil de empresa" in llm.received[1][-1].content
    assert "PERFIL DE EMPRESA" not in llm.received[0][0].content


async def test_cota_de_mensagens_acabou_responde_sem_chamar_a_ia():
    finance = FakeFinance(linked={PHONE: "Ana Souza"}, quota=1)
    handler, finance, llm = make_handler([AIMessage(content="Oi!")], finance=finance)

    assert await handler.handle(text("oi")) == "Oi!"
    reply = await handler.handle(text("gastei 10"))
    assert "limite de mensagens do dia" in reply
    assert len(llm.received) == 1
    assert finance.created == []


async def test_prompt_pede_respostas_curtas():
    handler, finance, llm = make_handler([AIMessage(content="ok")])
    await handler.handle(text("oi"))
    assert "No máximo 3 frases curtas" in llm.received[0][0].content
