"""Cliente da WhatsApp Cloud API (Meta). Docs: https://developers.facebook.com/docs/whatsapp/cloud-api"""

import hashlib
import hmac
from dataclasses import dataclass

import httpx


@dataclass
class IncomingMessage:
    id: str
    phone: str          # wa_id do remetente, ex.: 5511999999999
    type: str           # text | audio | image | document | ...
    text: str = ""      # corpo do texto ou legenda da mídia
    media_id: str | None = None
    mime: str = ""
    # Retomada depois que a instância que a processava caiu (ver coordination.claim_stale).
    recovered: bool = False


def parse_webhook(payload: dict) -> list[IncomingMessage]:
    messages = []
    for entry in payload.get("entry", []):
        for change in entry.get("changes", []):
            for m in change.get("value", {}).get("messages", []):
                msg = IncomingMessage(id=m["id"], phone=m["from"], type=m["type"])
                if m["type"] == "text":
                    msg.text = m["text"]["body"]
                elif m["type"] in ("audio", "image", "document", "video", "sticker"):
                    media = m[m["type"]]
                    msg.media_id = media.get("id")
                    msg.mime = media.get("mime_type", "")
                    msg.text = media.get("caption", "")
                messages.append(msg)
    return messages


def verify_signature(app_secret: str, body: bytes, header: str | None) -> bool:
    if not app_secret:
        return True  # validação desligada (apenas para desenvolvimento)
    expected = "sha256=" + hmac.new(app_secret.encode(), body, hashlib.sha256).hexdigest()
    return hmac.compare_digest(expected, header or "")


class WhatsAppClient:
    def __init__(self, token: str, phone_number_id: str, api_version: str = "v21.0"):
        self._phone_number_id = phone_number_id
        self._http = httpx.AsyncClient(
            base_url=f"https://graph.facebook.com/{api_version}",
            headers={"Authorization": f"Bearer {token}"},
            timeout=60,
        )

    async def aclose(self):
        await self._http.aclose()

    async def download_media(self, media_id: str) -> tuple[bytes, str]:
        meta = (await self._http.get(f"/{media_id}")).raise_for_status().json()
        res = (await self._http.get(meta["url"])).raise_for_status()
        return res.content, meta.get("mime_type", "")

    async def send_text(self, to: str, body: str) -> None:
        res = await self._http.post(f"/{self._phone_number_id}/messages", json={
            "messaging_product": "whatsapp",
            "to": to,
            "type": "text",
            "text": {"body": body[:4096]},
        })
        res.raise_for_status()
