"""Converte áudio, imagem e PDF em texto para o LLM (o DeepSeek só entende texto)."""

import asyncio
import io
import logging
from dataclasses import dataclass

from PIL import Image, ImageOps

log = logging.getLogger(__name__)


@dataclass
class MediaText:
    text: str
    # True quando o Whisper não teve segurança: o agente confirma os valores antes de registrar.
    low_confidence: bool = False


# Limites calibrados com áudios de teste: transcrições erradas ficaram com log-prob <= -0.83.
LOW_CONFIDENCE_LOGPROB = -0.7
HIGH_NO_SPEECH_PROB = 0.6
# Texto que se repete muito ("iFood, iFood, iFood") é sinal clássico de alucinação do Whisper.
HIGH_COMPRESSION_RATIO = 2.4


def is_low_confidence(segments) -> bool:
    """Média da log-probabilidade ponderada pela duração de cada trecho, mais os sinais de alucinação."""
    if not segments:
        return True
    duration = sum(max(s.end - s.start, 0.01) for s in segments)
    avg_logprob = sum(s.avg_logprob * max(s.end - s.start, 0.01) for s in segments) / duration
    return (avg_logprob < LOW_CONFIDENCE_LOGPROB
            or any(s.no_speech_prob > HIGH_NO_SPEECH_PROB for s in segments)
            or any(s.compression_ratio > HIGH_COMPRESSION_RATIO for s in segments))


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

    async def to_text(self, data: bytes, mime: str) -> MediaText:
        kind = kind_from_mime(mime)
        if kind == "audio":
            # Whisper/Tesseract são bloqueantes: roda fora do event loop.
            return await asyncio.to_thread(self._transcribe, data)
        fn = {"image": self._ocr, "pdf": self._pdf}.get(kind)
        if fn is None:
            raise ValueError(f"Tipo de mídia não suportado: {mime}")
        return MediaText(await asyncio.to_thread(fn, data))

    def _transcribe(self, data: bytes) -> MediaText:
        if self._whisper is None:
            from faster_whisper import WhisperModel  # import tardio: só carrega se chegar áudio

            name, device, compute_type = self._whisper_cfg
            log.info("Carregando modelo Whisper '%s'...", name)
            self._whisper = WhisperModel(name, device=device, compute_type=compute_type)
        # beam_size=5: busca mais cuidadosa que a gulosa. Sem initial_prompt de vocabulário: nos testes ele
        # fez o Whisper inventar valores ("cinquenta e dois" virou "cinquenta reais") e palavras.
        segments, _ = self._whisper.transcribe(io.BytesIO(data), language="pt", vad_filter=True, beam_size=5)
        segments = list(segments)
        text = " ".join(s.text.strip() for s in segments).strip()
        return MediaText(text, is_low_confidence(segments))

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
