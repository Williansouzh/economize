FROM python:3.12-slim

# Tesseract com português para ler prints e comprovantes
RUN apt-get update \
 && apt-get install -y --no-install-recommends tesseract-ocr tesseract-ocr-por \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY app/ app/

# O modelo do Whisper é baixado no primeiro áudio e fica em cache neste volume
ENV HF_HOME=/models
VOLUME /models
EXPOSE 8000
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
