from fastapi import APIRouter, Depends, HTTPException, Request, status
from pydantic import BaseModel, EmailStr, Field
import asyncpg

from ..db import get_conn
from ..security import (
    create_access_token,
    get_current_user,
    hash_password,
    verify_password,
)

router = APIRouter(prefix="/api/v1/auth", tags=["auth"])


class RegisterBody(BaseModel):
    name: str = Field(min_length=2, max_length=120)
    email: EmailStr
    password: str = Field(min_length=6, max_length=128)


class LoginBody(BaseModel):
    email: EmailStr
    password: str = Field(min_length=1, max_length=128)


def _user_dict(row: dict) -> dict:
    return {
        "id": str(row["id"]),
        "name": row["name"],
        "email": row["email"],
        "role": row["role"],
    }


@router.post("/register", status_code=status.HTTP_201_CREATED)
async def register(
    request: Request,
    body: RegisterBody,
    conn: asyncpg.Connection = Depends(get_conn),
):
    raw_json = await request.json()
    if "role" in raw_json and raw_json["role"] != "participant":
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Самостоятельное назначение роли запрещено",
        )

    email = body.email.lower().strip()
    existing = await conn.fetchval("SELECT id FROM users WHERE email = $1", email)
    if existing:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Пользователь с таким email уже зарегистрирован",
        )

    pw_hash = hash_password(body.password)
    row = await conn.fetchrow(
        """
        INSERT INTO users (name, email, password_hash, role)
        VALUES ($1, $2, $3, 'participant')
        RETURNING id, name, email, role
        """,
        body.name.strip(),
        email,
        pw_hash,
    )
    user = dict(row)
    token = create_access_token(str(user["id"]), user["role"])
    return {
        "access_token": token,
        "token_type": "bearer",
        "user": _user_dict(user),
    }


@router.post("/login")
async def login(
    body: LoginBody,
    conn: asyncpg.Connection = Depends(get_conn),
):
    email = body.email.lower().strip()
    row = await conn.fetchrow(
        "SELECT id, name, email, password_hash, role FROM users WHERE email = $1",
        email,
    )
    if not row or not verify_password(body.password, row["password_hash"]):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Неверный email или пароль",
        )
    user = dict(row)
    token = create_access_token(str(user["id"]), user["role"])
    return {
        "access_token": token,
        "token_type": "bearer",
        "user": _user_dict(user),
    }


@router.get("/me")
async def me(user: dict = Depends(get_current_user)):
    return _user_dict(user)


@router.patch("/me")
async def update_me(
    request: Request,
    user: dict = Depends(get_current_user),
    conn: asyncpg.Connection = Depends(get_conn),
):
    raw_json = await request.json()
    if "role" in raw_json or "used_at" in raw_json:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Изменение роли или служебных полей запрещено",
        )
    name = raw_json.get("name")
    if isinstance(name, str) and len(name.strip()) >= 2:
        row = await conn.fetchrow(
            "UPDATE users SET name = $1 WHERE id = $2 RETURNING id, name, email, role",
            name.strip(),
            user["id"],
        )
        return _user_dict(dict(row))
    return _user_dict(user)


@router.post("/logout")
async def logout(user: dict = Depends(get_current_user)):
    return {"ok": True}
