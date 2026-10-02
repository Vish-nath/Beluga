from __future__ import annotations

import hashlib
import json
import os
import re
import secrets
import socket
import sqlite3
import urllib.request
from contextlib import asynccontextmanager
from datetime import date, datetime, timedelta, timezone
from pathlib import Path
from typing import Annotated

from fastapi import Depends, FastAPI, Header, HTTPException, Query, status
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel, Field


ROOT = Path(__file__).resolve().parent.parent
STATIC_DIR = ROOT / "web"
DATABASE_PATH = Path(os.environ.get("HEALTHBOT_DB", ROOT / "data" / "healthbot.sqlite3"))
GOOGLE_CLIENT_ID = os.environ.get("GOOGLE_CLIENT_ID", "").strip()
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
                created_at TEXT NOT NULL,
                is_admin INTEGER NOT NULL DEFAULT 0
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
            CREATE TABLE IF NOT EXISTS patients (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
                patient_id TEXT UNIQUE NOT NULL,
                name TEXT NOT NULL,
                age INTEGER NOT NULL,
                gender TEXT NOT NULL DEFAULT '',
                phone TEXT NOT NULL DEFAULT '',
                email TEXT NOT NULL DEFAULT '',
                blood_group TEXT NOT NULL DEFAULT '',
                address TEXT NOT NULL DEFAULT '',
                emergency_contact TEXT NOT NULL DEFAULT '',
                chronic_conditions TEXT NOT NULL DEFAULT '[]',
                allergies TEXT NOT NULL DEFAULT '[]',
                current_medications TEXT NOT NULL DEFAULT '[]',
                notes TEXT NOT NULL DEFAULT '',
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL
            );
            CREATE TABLE IF NOT EXISTS patient_visits (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                patient_id INTEGER NOT NULL REFERENCES patients(id) ON DELETE CASCADE,
                user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
                visit_date TEXT NOT NULL,
                chief_complaint TEXT NOT NULL DEFAULT '',
                diagnosis TEXT NOT NULL DEFAULT '',
                systolic_bp INTEGER,
                diastolic_bp INTEGER,
                fasting_glucose REAL,
                heart_rate INTEGER,
                temperature REAL,
                weight_kg REAL,
                prescriptions TEXT NOT NULL DEFAULT '[]',
                clinical_notes TEXT NOT NULL DEFAULT '',
                next_followup TEXT,
                created_at TEXT NOT NULL
            );
            CREATE TABLE IF NOT EXISTS admin_access_log (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                admin_user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
                target_user_id INTEGER REFERENCES users(id) ON DELETE SET NULL,
                action TEXT NOT NULL,
                accessed_at TEXT NOT NULL
            );
            CREATE INDEX IF NOT EXISTS idx_patients_user ON patients(user_id);
            CREATE INDEX IF NOT EXISTS idx_visits_patient ON patient_visits(patient_id);
            """
        )
        user_columns = {row["name"] for row in connection.execute("PRAGMA table_info(users)")}
        if "is_admin" not in user_columns:
            connection.execute("ALTER TABLE users ADD COLUMN is_admin INTEGER NOT NULL DEFAULT 0")
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
    profile["conditions"] = json.loads(profile.pop("conditions", "[]"))
    profile["medications"] = json.loads(profile.pop("medications", "[]"))
    return profile


def patient_dict(row: sqlite3.Row | None) -> dict | None:
    if row is None:
        return None
    patient = dict(row)
    patient["chronic_conditions"] = json.loads(patient.pop("chronic_conditions", "[]"))
    patient["allergies"] = json.loads(patient.pop("allergies", "[]"))
    patient["current_medications"] = json.loads(patient.pop("current_medications", "[]"))
    return patient


def visit_dict(row: sqlite3.Row | None) -> dict | None:
    if row is None:
        return None
    visit = dict(row)
    visit["prescriptions"] = json.loads(visit.pop("prescriptions", "[]"))
    return visit


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
    blood_type: str = Field(default="", max_length=10)
    height_cm: float | None = Field(default=None, gt=40, le=260)
    weight_kg: float | None = Field(default=None, gt=2, le=400)
    location: str = Field(default="", max_length=120)
    conditions: list[str] = Field(default_factory=list, max_length=30)
    medications: list[str] = Field(default_factory=list, max_length=50)


class LoginInput(BaseModel):
    email: str = Field(min_length=3, max_length=254)
    password: str = Field(min_length=1, max_length=128)


class GoogleAuthInput(BaseModel):
    id_token: str | None = None
    email: str | None = None
    name: str | None = None


class ProfileInput(BaseModel):
    name: str = Field(min_length=1, max_length=80)
    age: int | None = Field(default=None, ge=1, le=120)
    gender: str = Field(default="", max_length=40)
    blood_type: str = Field(default="", max_length=10)
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


class PatientInput(BaseModel):
    patient_id: str | None = Field(default=None, max_length=50)
    name: str = Field(min_length=1, max_length=120)
    age: int = Field(ge=0, le=150)
    gender: str = Field(default="", max_length=40)
    phone: str = Field(default="", max_length=30)
    email: str = Field(default="", max_length=254)
    blood_group: str = Field(default="", max_length=10)
    address: str = Field(default="", max_length=255)
    emergency_contact: str = Field(default="", max_length=100)
    chronic_conditions: list[str] = Field(default_factory=list, max_length=50)
    allergies: list[str] = Field(default_factory=list, max_length=50)
    current_medications: list[str] = Field(default_factory=list, max_length=50)
    notes: str = Field(default="", max_length=1500)


class VisitInput(BaseModel):
    visit_date: str = Field(default="", max_length=30)
    chief_complaint: str = Field(default="", max_length=255)
    diagnosis: str = Field(default="", max_length=255)
    systolic_bp: int | None = Field(default=None, ge=30, le=350)
    diastolic_bp: int | None = Field(default=None, ge=20, le=250)
    fasting_glucose: float | None = Field(default=None, ge=10, le=1200)
    heart_rate: int | None = Field(default=None, ge=20, le=300)
    temperature: float | None = Field(default=None, ge=25.0, le=50.0)
    weight_kg: float | None = Field(default=None, ge=1.0, le=500.0)
    prescriptions: list[str] = Field(default_factory=list, max_length=50)
    clinical_notes: str = Field(default="", max_length=2000)
    next_followup: str | None = Field(default=None, max_length=30)


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


def authenticated_admin(user_id: CurrentUser) -> int:
    with connect_db() as connection:
        user = connection.execute("SELECT is_admin FROM users WHERE id = ?", (user_id,)).fetchone()
    if user is None or not user["is_admin"]:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Administrator access required.")
    return user_id


CurrentAdmin = Annotated[int, Depends(authenticated_admin)]


@asynccontextmanager
async def lifespan(_: FastAPI):
    initialize_database()
    yield


app = FastAPI(title="Beluga Health", version="0.2.0", lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

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
    return {"status": "ok", "storage": "local SQLite", "version": "0.2.0"}


@app.get("/api/system/network-info")
def get_network_info() -> dict:
    local_ips = []
    try:
        hostname = socket.gethostname()
        for ip in socket.gethostbyname_ex(hostname)[2]:
            if not ip.startswith("127."):
                local_ips.append(ip)
    except Exception:
        pass
    return {
        "hostname": socket.gethostname(),
        "local_ips": local_ips,
        "suggested_urls": [f"http://{ip}:8000/api" for ip in local_ips],
        "instructions": "Use any of these suggested URLs in the APK Server Settings when on the same Wi-Fi, or use your public tunnel URL (Cloudflare Tunnel / ngrok).",
    }


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
    return {
        "access_token": token,
        "user": {"id": user_id, "name": payload.name.strip(), "email": email, "is_admin": False},
        "profile": {
            "age": payload.age, "gender": payload.gender, "blood_type": payload.blood_type,
            "height_cm": payload.height_cm, "weight_kg": payload.weight_kg, "bmi": bmi,
            "location": payload.location.strip(), "conditions": payload.conditions, "medications": payload.medications
        },
    }


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
    return {"access_token": token, "user": {"id": user["id"], "name": user["name"], "email": user["email"], "is_admin": bool(user["is_admin"])}, "profile": profile_dict(profile)}


@app.post("/api/auth/google")
def google_auth(payload: GoogleAuthInput) -> dict:
    email = None
    name = None
    if not payload.id_token:
        raise HTTPException(status_code=401, detail="A verified Google ID token is required.")
    if not GOOGLE_CLIENT_ID:
        raise HTTPException(status_code=503, detail="Google sign-in is not configured on this server.")
    try:
        url = f"https://oauth2.googleapis.com/tokeninfo?id_token={payload.id_token}"
        with urllib.request.urlopen(url, timeout=5) as response:
            data = json.loads(response.read().decode())
        if data.get("aud") != GOOGLE_CLIENT_ID or data.get("email_verified") not in (True, "true"):
            raise ValueError("Google token audience or email verification did not match.")
        email = data.get("email")
        name = data.get("name") or (email.split("@")[0] if email else "")
    except Exception as error:
        raise HTTPException(status_code=401, detail="Invalid Google ID token.") from error

    if not email or not re.fullmatch(r"[^\s@]+@[^\s@]+\.[^\s@]+", email):
        raise HTTPException(status_code=422, detail="Valid Gmail or email address is required.")

    now = utc_now().isoformat()
    with connect_db() as connection:
        user = connection.execute("SELECT * FROM users WHERE email = ?", (email,)).fetchone()
        if user is None:
            dummy_hash, salt = hash_password(secrets.token_urlsafe(24))
            display_name = name or email.split("@")[0]
            cursor = connection.execute(
                "INSERT INTO users (name, email, password_hash, password_salt, created_at) VALUES (?, ?, ?, ?, ?)",
                (display_name, email, dummy_hash, salt, now),
            )
            user_id = int(cursor.lastrowid)
            connection.execute(
                "INSERT INTO profiles (user_id, updated_at) VALUES (?, ?)",
                (user_id, now),
            )
        else:
            user_id = int(user["id"])
            display_name = user["name"]

        token = create_access_token(connection, user_id)
        profile = connection.execute("SELECT * FROM profiles WHERE user_id = ?", (user_id,)).fetchone()

    return {
        "access_token": token,
        "user": {"id": user_id, "name": display_name, "email": email, "is_admin": bool(user["is_admin"]) if user else False},
        "profile": profile_dict(profile),
    }


@app.post("/api/logout", status_code=204)
def logout(user_id: CurrentUser, authorization: Annotated[str, Header()]) -> None:
    token_hash = hashlib.sha256(authorization[7:].encode()).hexdigest()
    with connect_db() as connection:
        connection.execute("DELETE FROM sessions WHERE token_hash = ? AND user_id = ?", (token_hash, user_id))


@app.get("/api/me")
def get_me(user_id: CurrentUser) -> dict:
    with connect_db() as connection:
        user = connection.execute("SELECT id, name, email, is_admin FROM users WHERE id = ?", (user_id,)).fetchone()
        profile = connection.execute("SELECT * FROM profiles WHERE user_id = ?", (user_id,)).fetchone()
    result = dict(user)
    result["is_admin"] = bool(result["is_admin"])
    return {"user": result, "profile": profile_dict(profile)}


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
        patients_count = connection.execute("SELECT COUNT(*) AS total FROM patients WHERE user_id = ?", (user_id,)).fetchone()["total"]
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
        "patients_count": patients_count, "dataset": dict(dataset) if dataset else None, "reading_notes": flags,
    }


@app.get("/api/admin/users")
def admin_list_users(admin_id: CurrentAdmin) -> list[dict]:
    with connect_db() as connection:
        connection.execute(
            "INSERT INTO admin_access_log (admin_user_id, action, accessed_at) VALUES (?, ?, ?)",
            (admin_id, "list_users", utc_now().isoformat()),
        )
        users = connection.execute(
            "SELECT id, name, email, created_at FROM users ORDER BY created_at DESC"
        ).fetchall()
    return [dict(user) for user in users]


@app.get("/api/admin/users/{target_user_id}")
def admin_get_user(target_user_id: int, admin_id: CurrentAdmin) -> dict:
    with connect_db() as connection:
        user = connection.execute(
            "SELECT id, name, email, created_at FROM users WHERE id = ?", (target_user_id,)
        ).fetchone()
        if user is None:
            raise HTTPException(status_code=404, detail="Account not found.")
        profile = connection.execute("SELECT * FROM profiles WHERE user_id = ?", (target_user_id,)).fetchone()
        measurements = connection.execute(
            "SELECT * FROM measurements WHERE user_id = ? ORDER BY recorded_at DESC", (target_user_id,)
        ).fetchall()
        reminders = connection.execute(
            "SELECT * FROM reminders WHERE user_id = ? ORDER BY scheduled_time", (target_user_id,)
        ).fetchall()
        patients = connection.execute(
            "SELECT * FROM patients WHERE user_id = ? ORDER BY updated_at DESC", (target_user_id,)
        ).fetchall()
        patient_records = []
        for patient_row in patients:
            patient = patient_dict(patient_row)
            visits = connection.execute(
                "SELECT * FROM patient_visits WHERE patient_id = ? AND user_id = ? ORDER BY visit_date DESC",
                (patient_row["id"], target_user_id),
            ).fetchall()
            patient["visits"] = [visit_dict(visit) for visit in visits]
            patient_records.append(patient)
        connection.execute(
            "INSERT INTO admin_access_log (admin_user_id, target_user_id, action, accessed_at) VALUES (?, ?, ?, ?)",
            (admin_id, target_user_id, "view_user_records", utc_now().isoformat()),
        )
    return {
        "user": dict(user),
        "profile": profile_dict(profile),
        "measurements": [dict(row) for row in measurements],
        "reminders": [dict(row) for row in reminders],
        "patients": patient_records,
    }


# ==========================================
# PATIENT MANAGEMENT ENDPOINTS
# ==========================================

@app.get("/api/patients")
def list_patients(user_id: CurrentUser, q: str | None = Query(default=None)) -> list[dict]:
    with connect_db() as connection:
        if q and q.strip():
            query_str = f"%{q.strip().lower()}%"
            rows = connection.execute(
                """
                SELECT p.*,
                       COUNT(v.id) AS visit_count,
                       MAX(v.visit_date) AS last_visit_date
                FROM patients p
                LEFT JOIN patient_visits v ON v.patient_id = p.id
                WHERE p.user_id = ?
                  AND (
                    LOWER(p.name) LIKE ?
                    OR LOWER(p.patient_id) LIKE ?
                    OR LOWER(p.phone) LIKE ?
                    OR LOWER(p.chronic_conditions) LIKE ?
                  )
                GROUP BY p.id
                ORDER BY p.updated_at DESC
                """,
                (user_id, query_str, query_str, query_str, query_str),
            ).fetchall()
        else:
            rows = connection.execute(
                """
                SELECT p.*,
                       COUNT(v.id) AS visit_count,
                       MAX(v.visit_date) AS last_visit_date
                FROM patients p
                LEFT JOIN patient_visits v ON v.patient_id = p.id
                WHERE p.user_id = ?
                GROUP BY p.id
                ORDER BY p.updated_at DESC
                """,
                (user_id,),
            ).fetchall()

    result = []
    for row in rows:
        p = patient_dict(row)
        p["visit_count"] = row["visit_count"]
        p["last_visit_date"] = row["last_visit_date"]
        result.append(p)
    return result


@app.post("/api/patients", status_code=201)
def create_patient(payload: PatientInput, user_id: CurrentUser) -> dict:
    now = utc_now().isoformat()
    with connect_db() as connection:
        pid = payload.patient_id.strip() if payload.patient_id and payload.patient_id.strip() else None
        if not pid:
            count = connection.execute("SELECT COUNT(*) AS total FROM patients").fetchone()["total"]
            candidate_id = f"PAT-{1001 + count}"
            while connection.execute("SELECT id FROM patients WHERE patient_id = ?", (candidate_id,)).fetchone():
                count += 1
                candidate_id = f"PAT-{1001 + count}"
            pid = candidate_id

        try:
            cursor = connection.execute(
                """
                INSERT INTO patients (
                    user_id, patient_id, name, age, gender, phone, email, blood_group,
                    address, emergency_contact, chronic_conditions, allergies,
                    current_medications, notes, created_at, updated_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    user_id, pid, payload.name.strip(), payload.age, payload.gender.strip(),
                    payload.phone.strip(), payload.email.strip().lower(), payload.blood_group.strip(),
                    payload.address.strip(), payload.emergency_contact.strip(),
                    json.dumps(payload.chronic_conditions), json.dumps(payload.allergies),
                    json.dumps(payload.current_medications), payload.notes.strip(), now, now,
                ),
            )
            row = connection.execute("SELECT * FROM patients WHERE id = ?", (cursor.lastrowid,)).fetchone()
        except sqlite3.IntegrityError as error:
            if "patients.patient_id" in str(error):
                raise HTTPException(status_code=409, detail=f"A patient with ID '{pid}' already exists.") from error
            raise

    p = patient_dict(row)
    p["visit_count"] = 0
    p["last_visit_date"] = None
    p["visits"] = []
    return p


@app.get("/api/patients/{patient_id}")
def get_patient(patient_id: str, user_id: CurrentUser) -> dict:
    with connect_db() as connection:
        row = connection.execute(
            "SELECT * FROM patients WHERE (id = ? OR patient_id = ?) AND user_id = ?",
            (patient_id, patient_id, user_id),
        ).fetchone()
        if row is None:
            raise HTTPException(status_code=404, detail="Patient not found.")
        visits = connection.execute(
            "SELECT * FROM patient_visits WHERE patient_id = ? ORDER BY visit_date DESC, id DESC",
            (row["id"],),
        ).fetchall()

    patient = patient_dict(row)
    patient["visits"] = [visit_dict(v) for v in visits]
    patient["visit_count"] = len(visits)
    patient["last_visit_date"] = visits[0]["visit_date"] if visits else None
    return patient


@app.put("/api/patients/{patient_id}")
def update_patient(patient_id: str, payload: PatientInput, user_id: CurrentUser) -> dict:
    now = utc_now().isoformat()
    with connect_db() as connection:
        existing = connection.execute(
            "SELECT id, patient_id FROM patients WHERE (id = ? OR patient_id = ?) AND user_id = ?",
            (patient_id, patient_id, user_id),
        ).fetchone()
        if existing is None:
            raise HTTPException(status_code=404, detail="Patient not found.")

        target_pid = payload.patient_id.strip() if payload.patient_id and payload.patient_id.strip() else existing["patient_id"]
        try:
            connection.execute(
                """
                UPDATE patients SET
                    patient_id = ?, name = ?, age = ?, gender = ?, phone = ?, email = ?,
                    blood_group = ?, address = ?, emergency_contact = ?, chronic_conditions = ?,
                    allergies = ?, current_medications = ?, notes = ?, updated_at = ?
                WHERE id = ? AND user_id = ?
                """,
                (
                    target_pid, payload.name.strip(), payload.age, payload.gender.strip(),
                    payload.phone.strip(), payload.email.strip().lower(), payload.blood_group.strip(),
                    payload.address.strip(), payload.emergency_contact.strip(),
                    json.dumps(payload.chronic_conditions), json.dumps(payload.allergies),
                    json.dumps(payload.current_medications), payload.notes.strip(), now,
                    existing["id"], user_id,
                ),
            )
        except sqlite3.IntegrityError as error:
            if "patients.patient_id" in str(error):
                raise HTTPException(status_code=409, detail=f"A patient with ID '{target_pid}' already exists.") from error
            raise

        row = connection.execute("SELECT * FROM patients WHERE id = ?", (existing["id"],)).fetchone()
        visits = connection.execute(
            "SELECT * FROM patient_visits WHERE patient_id = ? ORDER BY visit_date DESC, id DESC",
            (existing["id"],),
        ).fetchall()

    p = patient_dict(row)
    p["visits"] = [visit_dict(v) for v in visits]
    p["visit_count"] = len(visits)
    p["last_visit_date"] = visits[0]["visit_date"] if visits else None
    return p


@app.delete("/api/patients/{patient_id}", status_code=204)
def delete_patient(patient_id: str, user_id: CurrentUser) -> None:
    with connect_db() as connection:
        result = connection.execute(
            "DELETE FROM patients WHERE (id = ? OR patient_id = ?) AND user_id = ?",
            (patient_id, patient_id, user_id),
        )
        if result.rowcount == 0:
            raise HTTPException(status_code=404, detail="Patient not found.")


@app.post("/api/patients/{patient_id}/visits", status_code=201)
def add_patient_visit(patient_id: str, payload: VisitInput, user_id: CurrentUser) -> dict:
    now = utc_now().isoformat()
    visit_date = payload.visit_date.strip() if payload.visit_date and payload.visit_date.strip() else date.today().isoformat()
    with connect_db() as connection:
        patient = connection.execute(
            "SELECT id FROM patients WHERE (id = ? OR patient_id = ?) AND user_id = ?",
            (patient_id, patient_id, user_id),
        ).fetchone()
        if patient is None:
            raise HTTPException(status_code=404, detail="Patient not found.")

        cursor = connection.execute(
            """
            INSERT INTO patient_visits (
                patient_id, user_id, visit_date, chief_complaint, diagnosis,
                systolic_bp, diastolic_bp, fasting_glucose, heart_rate,
                temperature, weight_kg, prescriptions, clinical_notes,
                next_followup, created_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                patient["id"], user_id, visit_date, payload.chief_complaint.strip(),
                payload.diagnosis.strip(), payload.systolic_bp, payload.diastolic_bp,
                payload.fasting_glucose, payload.heart_rate, payload.temperature,
                payload.weight_kg, json.dumps(payload.prescriptions),
                payload.clinical_notes.strip(), payload.next_followup, now,
            ),
        )
        connection.execute("UPDATE patients SET updated_at = ? WHERE id = ?", (now, patient["id"]))
        row = connection.execute("SELECT * FROM patient_visits WHERE id = ?", (cursor.lastrowid,)).fetchone()

    return visit_dict(row)


@app.put("/api/patients/{patient_id}/visits/{visit_id}")
def update_patient_visit(patient_id: str, visit_id: int, payload: VisitInput, user_id: CurrentUser) -> dict:
    visit_date = payload.visit_date.strip() if payload.visit_date and payload.visit_date.strip() else date.today().isoformat()
    with connect_db() as connection:
        patient = connection.execute(
            "SELECT id FROM patients WHERE (id = ? OR patient_id = ?) AND user_id = ?",
            (patient_id, patient_id, user_id),
        ).fetchone()
        if patient is None:
            raise HTTPException(status_code=404, detail="Patient not found.")

        result = connection.execute(
            """
            UPDATE patient_visits SET
                visit_date = ?, chief_complaint = ?, diagnosis = ?,
                systolic_bp = ?, diastolic_bp = ?, fasting_glucose = ?,
                heart_rate = ?, temperature = ?, weight_kg = ?,
                prescriptions = ?, clinical_notes = ?, next_followup = ?
            WHERE id = ? AND patient_id = ? AND user_id = ?
            """,
            (
                visit_date, payload.chief_complaint.strip(), payload.diagnosis.strip(),
                payload.systolic_bp, payload.diastolic_bp, payload.fasting_glucose,
                payload.heart_rate, payload.temperature, payload.weight_kg,
                json.dumps(payload.prescriptions), payload.clinical_notes.strip(),
                payload.next_followup, visit_id, patient["id"], user_id,
            ),
        )
        if result.rowcount == 0:
            raise HTTPException(status_code=404, detail="Visit record not found.")

        connection.execute("UPDATE patients SET updated_at = ? WHERE id = ?", (utc_now().isoformat(), patient["id"]))
        row = connection.execute("SELECT * FROM patient_visits WHERE id = ?", (visit_id,)).fetchone()

    return visit_dict(row)


@app.delete("/api/patients/{patient_id}/visits/{visit_id}", status_code=204)
def delete_patient_visit(patient_id: str, visit_id: int, user_id: CurrentUser) -> None:
    with connect_db() as connection:
        patient = connection.execute(
            "SELECT id FROM patients WHERE (id = ? OR patient_id = ?) AND user_id = ?",
            (patient_id, patient_id, user_id),
        ).fetchone()
        if patient is None:
            raise HTTPException(status_code=404, detail="Patient not found.")

        result = connection.execute(
            "DELETE FROM patient_visits WHERE id = ? AND patient_id = ? AND user_id = ?",
            (visit_id, patient["id"], user_id),
        )
        if result.rowcount == 0:
            raise HTTPException(status_code=404, detail="Visit record not found.")


# ==========================================
# REMINDERS ENDPOINTS
# ==========================================

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