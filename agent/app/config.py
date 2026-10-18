from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    deepseek_api_key: str = ""
    deepseek_model: str = "deepseek-chat"

    finance_api_url: str = "http://localhost:5000"
    agent_api_key: str = ""

    whatsapp_token: str = ""
    whatsapp_phone_number_id: str = ""
    whatsapp_verify_token: str = ""
    whatsapp_app_secret: str = ""
    graph_api_version: str = "v21.0"

    whisper_model: str = "small"
    whisper_device: str = "cpu"
    whisper_compute_type: str = "int8"
    tesseract_lang: str = "por"

    # PostgreSQL para histórico, dedupe e fila por telefone. Vazio = tudo em memória (uma instância só).
    database_url: str = ""
    database_pool_size: int = 20

    # Tempo máximo para processar uma mensagem. Passado o dobro disso sem conclusão, outra
    # instância assume que quem a pegou caiu e processa de novo (até recovery_max_attempts vezes).
    processing_timeout_seconds: int = 300
    recovery_max_attempts: int = 3

    timezone: str = "America/Sao_Paulo"
    # Quantas mensagens do histórico vão para o LLM a cada turno.
    history_limit: int = 30


@lru_cache
def get_settings() -> Settings:
    return Settings()
