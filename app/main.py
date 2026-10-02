from __future__ import annotations

import hashlib
import json
import os
import re
import secrets
import sqlite3
from contextlib import asynccontextmanager
from datetime import date, datetime, timedelta, timezone
from pathlib import Path
from typing import Annotated

from fastapi import Depends, FastAPI, Header, HTTPException, status
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel, Field


ROOT = Path(__file__).resolve().parent.parent
STATIC_DIR = ROOT / "web"
DATABASE_PATH = Path(os.environ.get("HEALTHBOT_DB", ROOT / "data" / "healthbot.sqlite3"))
PASSWORD_ROUNDS = 310_000
TOKEN_LIFETIME = timedelta(days=14)


def connect_db() -> sqlite3.Connection:
    DATABASE_PATH.parent.mkdir(parents=True, exist_ok=True)
    connection = sqlite3.connect(DATABASE_PATH)
    connection.row_factory = sqlite3.Row
    connection.execute("PRAGMA foreign_keys = ON")
    return connection


def initialize_database() -> None:
    with connect_db() as connection:
        connection.executescript(
            """
            CREATE TABLE IF NOT EXISTS users (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                name TEXT NOT NULL,
                email TEXT NOT NULL UNIQUE COLLATE NOCASE,
                password_hash TEXT NOT NULL,
                password_salt TEXT NOT NULL,
                created_at TEXT NOT NULL
            );
            CREATE TABLE IF NOT EXISTS profiles (
                user_id INTEGER PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
                age INTEGER,
                gender TEXT NOT NULL DEFAULT '',
                blood_type TEXT NOT NULL DEFAULT '',
                height_cm REAL,
                weight_kg REAL,
                bmi REAL,
                location TEXT NOT NULL DEFAULT '',
                conditions TEXT NOT NULL DEFAULT '[]',
                medications TEXT NOT NULL DEFAULT '[]',
                updated_at TEXT NOT NULL
            );
            CREATE TABLE IF NOT EXISTS sessions (
                token_hash TEXT PRIMARY KEY,
                user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
                expires_at TEXT NOT NULL
            );
            CREATE TABLE IF NOT EXISTS measurements (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
                steps INTEGER,
                active_minutes INTEGER,
                sleep_hours REAL,
                fasting_glucose REAL,
                systolic_bp INTEGER,
                diastolic_bp INTEGER,
                recorded_at TEXT NOT NULL
            );
            CREATE TABLE IF NOT EXISTS reminders (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
                title TEXT NOT NULL,
                scheduled_time TEXT NOT NULL,
                instruction TEXT NOT NULL DEFAULT '',
                active INTEGER NOT NULL DEFAULT 1,
                created_at TEXT NOT NULL
            );
            CREATE TABLE IF NOT EXISTS reminder_completions (
                reminder_id INTEGER NOT NULL REFERENCES reminders(id) ON DELETE CASCADE,
                completed_on TEXT NOT NULL,
                PRIMARY KEY (reminder_id, completed_on)
            );
            CREATE TABLE IF NOT EXISTS dataset_summary (
                id INTEGER PRIMARY KEY CHECK (id = 1),
                record_count INTEGER NOT NULL,
                diabetes_count INTEGER NOT NULL,
                hypertension_count INTEGER NOT NULL,
                average_age REAL NOT NULL,
                average_bmi REAL NOT NULL,
                imported_at TEXT NOT NULL
            );
            """
        )
        profile_columns = {row["name"] for row in connection.execute("PRAGMA table_info(profiles)")}
        if "medications" not in profile_columns:
            connection.execute("ALTER TABLE profiles ADD COLUMN medications TEXT NOT NULL DEFAULT '[]'")
        if "blood_type" not in profile_columns:
            connection.execute("ALTER TABLE profiles ADD COLUMN blood_type TEXT NOT NULL DEFAULT ''")


def utc_now() -> datetime:
    return datetime.now(timezone.utc)


def hash_password(password: str, salt: bytes | None = None) -> tuple[str, str]:
    salt = salt or secrets.token_bytes(16)
    password_hash = hashlib.pbkdf2_hmac("sha256", password.encode(), salt, PASSWORD_ROUNDS)
    return password_hash.hex(), salt.hex()


def profile_dict(row: sqlite3.Row | None) -> dict | None:
    if row is None:
        return None
    profile = dict(row)
    profile["conditions"] = json.loads(profile.pop("conditions"))
    profile["medications"] = json.loads(profile.pop("medications"))
    return profile


def create_access_token(connection: sqlite3.Connection, user_id: int) -> str:
    token = secrets.token_urlsafe(32)
    expires_at = (utc_now() + TOKEN_LIFETIME).isoformat()
    token_hash = hashlib.sha256(token.encode()).hexdigest()
    connection.execute(
        "INSERT INTO sessions (token_hash, user_id, expires_at) VALUES (?, ?, ?)",
        (token_hash, user_id, expires_at),
    )
    return token


class AccountInput(BaseModel):
    name: str = Field(min_length=1, max_length=80)
    email: str = Field(min_length=3, max_length=254)
    password: str = Field(min_length=8, max_length=128)
    age: int | None = Field(default=None, ge=1, le=120)
    gender: str = Field(default="", max_length=40)
    blood_type: str = Field(default="", max_length=3)
    height_cm: float | None = Field(default=None, gt=40, le=260)
    weight_kg: float | None = Field(default=None, gt=2, le=400)
    location: str = Field(default="", max_length=120)
    conditions: list[str] = Field(default_factory=list, max_length=30)
    medications: list[str] = Field(default_factory=list, max_length=50)


class LoginInput(BaseModel):
    email: str = Field(min_length=3, max_length=254)
    password: str = Field(min_length=1, max_length=128)


class ProfileInput(BaseModel):
    name: str = Field(min_length=1, max_length=80)
    age: int | None = Field(default=None, ge=1, le=120)
    gender: str = Field(default="", max_length=40)
    blood_type: str = Field(default="", max_length=3)
    height_cm: float | None = Field(default=None, gt=40, le=260)
    weight_kg: float | None = Field(default=None, gt=2, le=400)
    location: str = Field(default="", max_length=120)
    conditions: list[str] = Field(default_factory=list, max_length=30)
    medications: list[str] = Field(default_factory=list, max_length=50)


class MeasurementInput(BaseModel):
    steps: int | None = Field(default=None, ge=0, le=200_000)
    active_minutes: int | None = Field(default=None, ge=0, le=1_440)
    sleep_hours: float | None = Field(default=None, ge=0, le=24)
    fasting_glucose: float | None = Field(default=None, ge=20, le=1_000)
    systolic_bp: int | None = Field(default=None, ge=50, le=300)
    diastolic_bp: int | None = Field(default=None, ge=30, le=200)


class ReminderInput(BaseModel):
    title: str = Field(min_length=1, max_length=100)
    scheduled_time: str = Field(pattern=r"^([01]\d|2[0-3]):[0-5]\d$")
    instruction: str = Field(default="", max_length=120)


def authenticated_user(authorization: Annotated[str | None, Header()] = None) -> int:
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Please sign in.")
    token = authorization[7:]
    token_hash = hashlib.sha256(token.encode()).hexdigest()
    with connect_db() as connection:
        session = connection.execute(
            "SELECT user_id, expires_at FROM sessions WHERE token_hash = ?", (token_hash,)
        ).fetchone()
        if session is None or datetime.fromisoformat(session["expires_at"]) <= utc_now():
            if session is not None:
                connection.execute("DELETE FROM sessions WHERE token_hash = ?", (token_hash,))
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Session expired. Please sign in again.")
        return int(session["user_id"])


CurrentUser = Annotated[int, Depends(authenticated_user)]


@asynccontextmanager
async def lifespan(_: FastAPI):
    initialize_database()
    yield


app = FastAPI(title="Beluga Health", version="0.1.0", lifespan=lifespan)
app.mount("/static", StaticFiles(directory=STATIC_DIR), name="static")


@app.get("/")
def home() -> FileResponse:
    return FileResponse(STATIC_DIR / "index.html")


@app.get("/manifest.webmanifest")
def manifest() -> FileResponse:
    return FileResponse(STATIC_DIR / "manifest.webmanifest", media_type="application/manifest+json")


@app.get("/service-worker.js")
def service_worker() -> FileResponse:
    return FileResponse(STATIC_DIR / "service-worker.js", media_type="application/javascript")


@app.get("/api/health")
def health_check() -> dict[str, str]:
    return {"status": "ok", "storage": "local SQLite"}


@app.post("/api/register")
def register(payload: AccountInput) -> dict:
    email = payload.email.strip().lower()
    if not re.fullmatch(r"[^\s@]+@[^\s@]+\.[^\s@]+", email):
        raise HTTPException(status_code=422, detail="Enter a valid email address.")
    password_hash, salt = hash_password(payload.password)
    bmi = round(payload.weight_kg / ((payload.height_cm / 100) ** 2), 1) if payload.weight_kg and payload.height_cm else None
    now = utc_now().isoformat()
    try:
        with connect_db() as connection:
            cursor = connection.execute(
                "INSERT INTO users (name, email, password_hash, password_salt, created_at) VALUES (?, ?, ?, ?, ?)",
                (payload.name.strip(), email, password_hash, salt, now),
            )
            user_id = int(cursor.lastrowid)
            connection.execute(
                "INSERT INTO profiles (user_id, age, gender, blood_type, height_cm, weight_kg, bmi, location, conditions, medications, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                (user_id, payload.age, payload.gender.strip(), payload.blood_type.strip(), payload.height_cm, payload.weight_kg, bmi,
                 payload.location.strip(), json.dumps(payload.conditions), json.dumps(payload.medications), now),
            )
            token = create_access_token(connection, user_id)
    except sqlite3.IntegrityError as error:
        if "users.email" in str(error):
            raise HTTPException(status_code=409, detail="An account already exists for this email.") from error
        raise
    return {"access_token": token, "user": {"id": user_id, "name": payload.name.strip(), "email": email}, "profile": {"age": payload.age, "gender": payload.gender, "blood_type": payload.blood_type, "height_cm": payload.height_cm, "weight_kg": payload.weight_kg, "bmi": bmi, "location": payload.location.strip(), "conditions": payload.conditions, "medications": payload.medications}}


@app.post("/api/login")
def login(payload: LoginInput) -> dict:
    email = payload.email.strip().lower()
    with connect_db() as connection:
        user = connection.execute("SELECT * FROM users WHERE email = ?", (email,)).fetchone()
        if user is None:
            raise HTTPException(status_code=401, detail="Email or password is incorrect.")
        supplied_hash, _ = hash_password(payload.password, bytes.fromhex(user["password_salt"]))
        if not secrets.compare_digest(supplied_hash, user["password_hash"]):
            raise HTTPException(status_code=401, detail="Email or password is incorrect.")
        token = create_access_token(connection, int(user["id"]))
        profile = connection.execute("SELECT * FROM profiles WHERE user_id = ?", (user["id"],)).fetchone()
    return {"access_token": token, "user": {"id": user["id"], "name": user["name"], "email": user["email"]}, "profile": profile_dict(profile)}


@app.post("/api/logout", status_code=204)
def logout(user_id: CurrentUser, authorization: Annotated[str, Header()]) -> None:
    token_hash = hashlib.sha256(authorization[7:].encode()).hexdigest()
    with connect_db() as connection:
        connection.execute("DELETE FROM sessions WHERE token_hash = ? AND user_id = ?", (token_hash, user_id))


@app.get("/api/me")
def get_me(user_id: CurrentUser) -> dict:
    with connect_db() as connection:
        user = connection.execute("SELECT id, name, email FROM users WHERE id = ?", (user_id,)).fetchone()
        profile = connection.execute("SELECT * FROM profiles WHERE user_id = ?", (user_id,)).fetchone()
    return {"user": dict(user), "profile": profile_dict(profile)}


@app.put("/api/profile")
def update_profile(payload: ProfileInput, user_id: CurrentUser) -> dict:
    bmi = round(payload.weight_kg / ((payload.height_cm / 100) ** 2), 1) if payload.weight_kg and payload.height_cm else None
    with connect_db() as connection:
        connection.execute("UPDATE users SET name = ? WHERE id = ?", (payload.name.strip(), user_id))
        connection.execute(
            "UPDATE profiles SET age = ?, gender = ?, blood_type = ?, height_cm = ?, weight_kg = ?, bmi = ?, location = ?, conditions = ?, medications = ?, updated_at = ? WHERE user_id = ?",
            (payload.age, payload.gender.strip(), payload.blood_type.strip(), payload.height_cm, payload.weight_kg, bmi,
             payload.location.strip(), json.dumps(payload.conditions), json.dumps(payload.medications), utc_now().isoformat(), user_id),
        )
        profile = connection.execute("SELECT * FROM profiles WHERE user_id = ?", (user_id,)).fetchone()
    return profile_dict(profile) or {}


@app.post("/api/measurements", status_code=201)
def add_measurement(payload: MeasurementInput, user_id: CurrentUser) -> dict:
    values = payload.model_dump(exclude_none=True)
    if not values:
        raise HTTPException(status_code=422, detail="Add at least one measurement.")
    columns = list(values)
    with connect_db() as connection:
        cursor = connection.execute(
            f"INSERT INTO measurements (user_id, {', '.join(columns)}, recorded_at) VALUES ({', '.join('?' for _ in range(len(columns) + 2))})",
            [user_id, *values.values(), utc_now().isoformat()],
        )
        measurement = connection.execute("SELECT * FROM measurements WHERE id = ?", (cursor.lastrowid,)).fetchone()
    return dict(measurement)


@app.get("/api/dashboard")
def dashboard(user_id: CurrentUser) -> dict:
    today = date.today().isoformat()
    with connect_db() as connection:
        profile = connection.execute("SELECT * FROM profiles WHERE user_id = ?", (user_id,)).fetchone()
        user = connection.execute("SELECT name FROM users WHERE id = ?", (user_id,)).fetchone()
        measurements = connection.execute(
            "SELECT * FROM measurements WHERE user_id = ? ORDER BY recorded_at DESC LIMIT 7", (user_id,)
        ).fetchall()
        reminders = connection.execute(
            """SELECT r.*, EXISTS(SELECT 1 FROM reminder_completions c
               WHERE c.reminder_id = r.id AND c.completed_on = ?) AS completed_today
               FROM reminders r WHERE r.user_id = ? AND r.active = 1 ORDER BY r.scheduled_time""",
            (today, user_id),
        ).fetchall()
        dataset = connection.execute("SELECT * FROM dataset_summary WHERE id = 1").fetchone()
    latest = dict(measurements[0]) if measurements else None
    flags = []
    if latest:
        if latest["fasting_glucose"] is not None and latest["fasting_glucose"] >= 126:
            flags.append("This fasting glucose reading is above a commonly used reference threshold. A clinician must interpret and confirm results.")
        if latest["systolic_bp"] is not None and latest["diastolic_bp"] is not None and (latest["systolic_bp"] >= 130 or latest["diastolic_bp"] >= 80):
            flags.append("This blood pressure reading is elevated under common adult guidance. Repeat it correctly and discuss it with a clinician.")
    return {
        "name": user["name"], "profile": profile_dict(profile), "latest_measurement": latest,
        "measurements": [dict(row) for row in measurements], "reminders": [dict(row) for row in reminders],
        "dataset": dict(dataset) if dataset else None, "reading_notes": flags,
    }


@app.get("/api/reminders")
def list_reminders(user_id: CurrentUser) -> list[dict]:
    today = date.today().isoformat()
    with connect_db() as connection:
        rows = connection.execute(
            """SELECT r.*, EXISTS(SELECT 1 FROM reminder_completions c
               WHERE c.reminder_id = r.id AND c.completed_on = ?) AS completed_today
               FROM reminders r WHERE r.user_id = ? AND r.active = 1 ORDER BY r.scheduled_time""",
            (today, user_id),
        ).fetchall()
    return [dict(row) for row in rows]


@app.post("/api/reminders", status_code=201)
def add_reminder(payload: ReminderInput, user_id: CurrentUser) -> dict:
    with connect_db() as connection:
        cursor = connection.execute(
            "INSERT INTO reminders (user_id, title, scheduled_time, instruction, created_at) VALUES (?, ?, ?, ?, ?)",
            (user_id, payload.title.strip(), payload.scheduled_time, payload.instruction.strip(), utc_now().isoformat()),
        )
        row = connection.execute("SELECT * FROM reminders WHERE id = ?", (cursor.lastrowid,)).fetchone()
    return dict(row)


@app.post("/api/reminders/{reminder_id}/complete", status_code=204)
def complete_reminder(reminder_id: int, user_id: CurrentUser) -> None:
    with connect_db() as connection:
        reminder = connection.execute("SELECT id FROM reminders WHERE id = ? AND user_id = ? AND active = 1", (reminder_id, user_id)).fetchone()
        if reminder is None:
            raise HTTPException(status_code=404, detail="Reminder not found.")
        connection.execute(
            "INSERT OR IGNORE INTO reminder_completions (reminder_id, completed_on) VALUES (?, ?)",
            (reminder_id, date.today().isoformat()),
        )


@app.delete("/api/reminders/{reminder_id}", status_code=204)
def delete_reminder(reminder_id: int, user_id: CurrentUser) -> None:
    with connect_db() as connection:
        result = connection.execute("DELETE FROM reminders WHERE id = ? AND user_id = ?", (reminder_id, user_id))
        if result.rowcount == 0:
            raise HTTPException(status_code=404, detail="Reminder not found.")


@app.get("/{path:path}")
def frontend_fallback(path: str) -> FileResponse:
    return FileResponse(STATIC_DIR / "index.html")