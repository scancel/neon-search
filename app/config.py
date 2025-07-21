# ------------------------------------------------------------------
# app/config.py
#
# Manages application configuration using environment variables.
# ------------------------------------------------------------------
from typing import Optional

from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    # OpenSearch Configuration
    OPENSEARCH_HOST: str
    OPENSEARCH_USER: str = "neouser"
    OPENSEARCH_PASSWORD: str
    OPENSEARCH_INDEX: str = "user-profiles"

    # LLM Configuration (Optional)
    OPENAI_API_KEY: Optional[str] = None

    class Config:
        env_file = ".env"  # Load variables from a .env file


settings = Settings()
