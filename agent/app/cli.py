"""Converse com o agente pelo terminal, sem WhatsApp (útil para testar).

    python -m app.cli --phone 5511999999999

Comandos:  /audio caminho.ogg   /imagem caminho.png   /pdf caminho.pdf   /sair
Para vincular o número, gere o código no app e digite:  VINCULAR 123456
"""

import argparse
import asyncio
import mimetypes
import uuid
from pathlib import Path

from langchain_deepseek import ChatDeepSeek
from langgraph.checkpoint.memory import InMemorySaver

from .config import get_settings
from .finance_api import FinanceApi
from .graph import Deps, build_graph
from .media import MediaProcessor
from .service import MessageHandler
from .whatsapp import IncomingMessage


async def load_local_file(path: str) -> tuple[bytes, str]:
    return Path(path).read_bytes(), mimetypes.guess_type(path)[0] or ""


async def main(phone: str):
    s = get_settings()
    finance = FinanceApi(s.finance_api_url, s.agent_api_key)
    deps = Deps(
        llm=ChatDeepSeek(model=s.deepseek_model, api_key=s.deepseek_api_key, temperature=0.2),
        finance=finance,
        media=MediaProcessor(s.whisper_model, s.whisper_device, s.whisper_compute_type, s.tesseract_lang),
        load_media=load_local_file,
        timezone=s.timezone,
    )
    handler = MessageHandler(build_graph(deps, InMemorySaver()), finance)
    print(f"Agente pronto (telefone {phone}). Digite /sair para encerrar.\n")

    while True:
        line = (await asyncio.to_thread(input, "você> ")).strip()
        if not line:
            continue
        if line == "/sair":
            break
        cmd, _, arg = line.partition(" ")
        if cmd in ("/audio", "/imagem", "/pdf"):
            kind = {"/audio": "audio", "/imagem": "image", "/pdf": "document"}[cmd]
            msg = IncomingMessage(id=str(uuid.uuid4()), phone=phone, type=kind, media_id=arg.strip(),
                                  mime=mimetypes.guess_type(arg.strip())[0] or "")
        else:
            msg = IncomingMessage(id=str(uuid.uuid4()), phone=phone, type="text", text=line)
        print(f"bot> {await handler.handle(msg)}\n")

    await finance.aclose()


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--phone", default="5500000000000")
    asyncio.run(main(parser.parse_args().phone))
