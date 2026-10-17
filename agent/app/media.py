"""Converte áudio, imagem e PDF em texto para o LLM (o DeepSeek só entende texto)."""

import asyncio
import io
import logging

from PIL import Image, ImageOps

log = logging.getLogger(__name__)


def kind_from_mime(mime: str) -> str | None:
    mime = (mime or "").split(";")[0].strip().lower()
    if mime.startswith("audio/"):
        return "audio"
    if mime.startswith("image/"):
        return "image"
    if mime == "application/pdf":
        return "pdf"
    return None


class MediaProcessor:
    def __init__(self, whisper_model: str = "small", device: str = "cpu",
                 compute_type: str = "int8", tesseract_lang: str = "por"):
        self._whisper_cfg = (whisper_model, device, compute_type)
        self._whisper = None
        self._lang = tesseract_lang

    async def to_text(self, data: bytes, mime: str) -> str:
        kind = kind_from_mime(mime)
        fn = {"audio": self._transcribe, "image": self._ocr, "pdf": self._pdf}.get(kind)
        if fn is None:
            raise ValueError(f"Tipo de mídia não suportado: {mime}")
        # Whisper/Tesseract são bloqueantes: roda fora do event loop.
        return await asyncio.to_thread(fn, data)

    def _transcribe(self, data: bytes) -> str:
        if self._whisper is None:
            from faster_whisper import WhisperModel  # import tardio: só carrega se chegar áudio

            name, device, compute_type = self._whisper_cfg
            log.info("Carregando modelo Whisper '%s'...", name)
            self._whisper = WhisperModel(name, device=device, compute_type=compute_type)
        segments, _ = self._whisper.transcribe(io.BytesIO(data), language="pt", vad_filter=True)
        return " ".join(s.text.strip() for s in segments).strip()

    def _ocr(self, data: bytes) -> str:
        import pytesseract

        img = ImageOps.exif_transpose(Image.open(io.BytesIO(data))).convert("L")
        # Prints de celular costumam ter fonte pequena: ampliar melhora bastante o OCR.
        if img.width < 1500:
            factor = 1500 / img.width
            img = img.resize((int(img.width * factor), int(img.height * factor)), Image.LANCZOS)
        return pytesseract.image_to_string(img, lang=self._lang).strip()

    def _pdf(self, data: bytes) -> str:
        from pypdf import PdfReader

        reader = PdfReader(io.BytesIO(data))
        return "\n".join((page.extract_text() or "") for page in reader.pages[:5]).strip()
