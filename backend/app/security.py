import base64
import hashlib
import secrets
from datetime import datetime, timedelta, timezone
from typing import Callable
from uuid import UUID

import asyncpg
from cryptography.fernet import Fernet
from fastapi import Depends, HTTPException, Query, Request, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from jose import JWTError, jwt
from passlib.context import CryptContext

from .config import settings
from .db import get_conn

pwd_ctx = CryptContext(schemes=["bcrypt"], deprecated="auto")
bearer_scheme = HTTPBearer(auto_error=False)


def _get_fernet() -> Fernet:
    key = settings.token_encryption_key.encode()
    try:
        return Fernet(key)
    except Exception:
        derived = base64.urlsafe_b64encode(hashlib.sha256(key).digest())
        return Fernet(derived)


_fernet = _get_fernet()


def hash_password(password: str) -> str:
    return pwd_ctx.hash(password)


def verify_password(password: str, password_hash: str) -> bool:
    return pwd_ctx.verify(password, password_hash)


def generate_ticket_token() -> tuple[str, str, str]:
    raw = f"EF1:{secrets.token_hex(16)}"
    token_hash = hashlib.sha256(raw.encode()).hexdigest()
    token_encrypted = _fernet.encrypt(raw.encode()).decode()
    return raw, token_hash, token_encrypted


def hash_ticket_token(raw_token: str) -> str:
    return hashlib.sha256(raw_token.encode()).hexdigest()


def decrypt_ticket_token(token_encrypted: str) -> str:
    return _fernet.decrypt(token_encrypted.encode()).decode()


def is_valid_qr_format(raw_token: str) -> bool:
    if not raw_token.startswith("EF1:"):
        return False
    secret_part = raw_token[4:]
    if len(secret_part) != 32:
        return False
    try:
        int(secret_part, 16)
        return True
    except ValueError:
        return False


def create_access_token(user_id: str, role: str) -> str:
    now = datetime.now(timezone.utc)
    payload = {
        "sub": user_id,
        "role": role,
        "iat": int(now.timestamp()),
        "exp": int((now + timedelta(minutes=settings.jwt_expire_minutes)).timestamp()),
    }
    return jwt.encode(payload, settings.jwt_secret, algorithm=settings.jwt_algorithm)


def decode_access_token(token: str) -> dict:
    try:
        return jwt.decode(
            token, settings.jwt_secret, algorithms=[settings.jwt_algorithm]
        )
    except JWTError as exc:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Недействительная или истёкшая сессия",
        ) from exc


async def get_current_user(
    credentials: HTTPAuthorizationCredentials | None = Depends(bearer_scheme),
    token: str | None = Query(default=None),
    conn: asyncpg.Connection = Depends(get_conn),
) -> dict:
    raw_jwt = credentials.credentials if credentials else token
    if not raw_jwt:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Требуется авторизация",
        )
    payload = decode_access_token(raw_jwt)
    user_id = payload.get("sub")
    if not user_id:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Недействительный токен",
        )
    row = await conn.fetchrow(
        "SELECT id, name, email, role, created_at FROM users WHERE id = $1",
        UUID(user_id),
    )
    if not row:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Пользователь не найден",
        )
    return dict(row)


def require_role(*roles: str) -> Callable:
    async def _checker(user: dict = Depends(get_current_user)) -> dict:
        if user["role"] not in roles:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Недостаточно прав для выполнения операции",
            )
        return user

    return _checker
