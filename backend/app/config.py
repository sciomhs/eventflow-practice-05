import os
from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    database_url: str = os.getenv(
        "DATABASE_URL",
        "postgresql://eventflow:eventflow_dev@localhost:5432/eventflow",
    ).replace("postgresql+asyncpg://", "postgresql://")
    jwt_secret: str = os.getenv(
        "JWT_SECRET",
        "dev-only-change-in-production-min-32-chars",
    )
    jwt_algorithm: str = "HS256"
    jwt_expire_minutes: int = 60 * 24
    token_encryption_key: str = os.getenv(
        "TOKEN_ENCRYPTION_KEY",
        "dev-only-fernet-key-placeholder-32-bytes=",
    )
    server_host: str = os.getenv("SERVER_HOST", "0.0.0.0")
    server_port: int = int(os.getenv("SERVER_PORT", "8000"))


settings = Settings()
