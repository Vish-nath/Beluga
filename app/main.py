from __future__ import annotations

import hashlib
import json
import os
import re
import secrets
import socket
import urllib.request
from contextlib import asynccontextmanager
from datetime import date, datetime, timedelta, timezone
from pathlib import Path
from typing import Annotated

from fastapi import Depends, FastAPI, Header, HTTPException, Query, status
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles
from pymongo.database import Database
from pymongo.errors import DuplicateKeyError
from pydantic import BaseModel, Field

from app.database import close_client, connect_db, initialize_database, next_id

ROOT = Path(__file__).resolve().parent.parent
STATIC_DIR = ROOT / "web"
GOOGLE_CLIENT_ID = os.environ.get("GOOGLE_CLIENT_ID", "").strip()
PASSWORD_ROUNDS = 310_000
TOKEN_LIFETIME = timedelta(days=14)


def document_dict(document: dict | None) -> dict | None:
    if document is None:
        return None
    return {key: value for key, value in document.items() if key != "_id"}


def insert_record(database: Database, collection: str, values: dict) -> dict:
    document = {**values, "id": next_id(database, collection)}
    database[collection].insert_one(document)
    return document


def utc_now() -> datetime:
    return datetime.now(timezone.utc)


def hash_password(password: str, salt: bytes | None = None) -> tuple[str, str]:
    salt = salt or secrets.token_bytes(16)
    password_hash = hashlib.pbkdf2_hmac("sha256", password.encode(), salt, PASSWORD_ROUNDS)
    return password_hash.hex(), salt.hex()


def profile_dict(row: dict | None) -> dict | None:
    return document_dict(row)


def patient_dict(row: dict | None) -> dict | None:
    return document_dict(row)


def visit_dict(row: dict | None) -> dict | None:
    return document_dict(row)


def patient_query(patient_id: str, user_id: int) -> dict:
    selectors = [{"patient_id": patient_id}]
    try:
        selectors.append({"id": int(patient_id)})
    except ValueError:
        pass
    return {"user_id": user_id, "$or": selectors}


def create_access_token(database: Database, user_id: int) -> str:
    token = secrets.token_urlsafe(32)
    expires_at = (utc_now() + TOKEN_LIFETIME).isoformat()
    token_hash = hashlib.sha256(token.encode()).hexdigest()
    database.sessions.insert_one({"token_hash": token_hash, "user_id": user_id, "expires_at": expires_at})
    return token


class PrescriptionInput(BaseModel):
    id: str = Field(default_factory=lambda: secrets.token_hex(8), min_length=1, max_length=32)
    name: str = Field(min_length=1, max_length=100)
    prescribed_dose: str = Field(default="", max_length=100)
    quantity: str = Field(default="", max_length=60)
    intake_times: list[str] = Field(default_factory=list, max_length=8)
    instructions: str = Field(default="", max_length=240)


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
    appetite: str = Field(default="", max_length=500)
    daily_routine: str = Field(default="", max_length=2000)
    family_history: str = Field(default="", max_length=2000)
    prescriptions: list[PrescriptionInput] = Field(default_factory=list, max_length=30)
    profile_image: str = Field(default="", max_length=1_500_000)


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


class PrescriptionCompletionInput(BaseModel):
    prescription_id: str = Field(min_length=1, max_length=32)
    scheduled_time: str = Field(pattern=r"^([01]\d|2[0-3]):[0-5]\d$")
    completed_on: str = Field(pattern=r"^\d{4}-\d{2}-\d{2}$")


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
    with connect_db() as database:
        session = database.sessions.find_one({"token_hash": token_hash})
        if session is None or datetime.fromisoformat(session["expires_at"]) <= utc_now():
            if session is not None:
                database.sessions.delete_one({"token_hash": token_hash})
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Session expired. Please sign in again.")
        return int(session["user_id"])


CurrentUser = Annotated[int, Depends(authenticated_user)]


def authenticated_admin(user_id: CurrentUser) -> int:
    with connect_db() as database:
        user = database.users.find_one({"id": user_id}, {"is_admin": 1})
    if user is None or not user["is_admin"]:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Administrator access required.")
    return user_id


CurrentAdmin = Annotated[int, Depends(authenticated_admin)]


@asynccontextmanager
async def lifespan(_: FastAPI):
    try:
        initialize_database()
        yield
    finally:
        close_client()


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
    return {"status": "ok", "storage": "MongoDB", "version": "0.2.0"}


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
        with connect_db() as database:
            user = insert_record(database, "users", {
                "name": payload.name.strip(), "email": email, "password_hash": password_hash,
                "password_salt": salt, "created_at": now, "is_admin": False,
            })
            user_id = user["id"]
            database.profiles.insert_one({
                "user_id": user_id, "age": payload.age, "gender": payload.gender.strip(),
                "blood_type": payload.blood_type.strip(), "height_cm": payload.height_cm,
                "weight_kg": payload.weight_kg, "bmi": bmi, "location": payload.location.strip(),
                "conditions": payload.conditions, "medications": payload.medications,
                "updated_at": now,
            })
            token = create_access_token(database, user_id)
    except DuplicateKeyError as error:
        raise HTTPException(status_code=409, detail="An account already exists for this email.") from error
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
    with connect_db() as database:
        user = database.users.find_one({"email": email})
        if user is None:
            raise HTTPException(status_code=401, detail="Email or password is incorrect.")
        supplied_hash, _ = hash_password(payload.password, bytes.fromhex(user["password_salt"]))
        if not secrets.compare_digest(supplied_hash, user["password_hash"]):
            raise HTTPException(status_code=401, detail="Email or password is incorrect.")
        token = create_access_token(database, int(user["id"]))
        profile = database.profiles.find_one({"user_id": user["id"]})
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
    email = email.lower()

    now = utc_now().isoformat()
    with connect_db() as database:
        user = database.users.find_one({"email": email})
        if user is None:
            dummy_hash, salt = hash_password(secrets.token_urlsafe(24))
            display_name = name or email.split("@")[0]
            user = insert_record(database, "users", {
                "name": display_name, "email": email, "password_hash": dummy_hash,
                "password_salt": salt, "created_at": now, "is_admin": False,
            })
            user_id = user["id"]
            database.profiles.insert_one({"user_id": user_id, "updated_at": now})
        else:
            user_id = int(user["id"])
            display_name = user["name"]

        token = create_access_token(database, user_id)
        profile = database.profiles.find_one({"user_id": user_id})

    return {
        "access_token": token,
        "user": {"id": user_id, "name": display_name, "email": email, "is_admin": bool(user["is_admin"]) if user else False},
        "profile": profile_dict(profile),
    }


@app.post("/api/logout", status_code=204)
def logout(user_id: CurrentUser, authorization: Annotated[str, Header()]) -> None:
    token_hash = hashlib.sha256(authorization[7:].encode()).hexdigest()
    with connect_db() as database:
        database.sessions.delete_one({"token_hash": token_hash, "user_id": user_id})


@app.get("/api/me")
def get_me(user_id: CurrentUser) -> dict:
    with connect_db() as database:
        user = database.users.find_one({"id": user_id}, {"_id": 0, "id": 1, "name": 1, "email": 1, "is_admin": 1})
        profile = database.profiles.find_one({"user_id": user_id})
    result = dict(user)
    result["is_admin"] = bool(result["is_admin"])
    return {"user": result, "profile": profile_dict(profile)}


@app.put("/api/profile")
def update_profile(payload: ProfileInput, user_id: CurrentUser) -> dict:
    bmi = round(payload.weight_kg / ((payload.height_cm / 100) ** 2), 1) if payload.weight_kg and payload.height_cm else None
    with connect_db() as database:
        database.users.update_one({"id": user_id}, {"$set": {"name": payload.name.strip()}})
        database.profiles.update_one(
            {"user_id": user_id},
            {"$set": {
                "age": payload.age, "gender": payload.gender.strip(), "blood_type": payload.blood_type.strip(),
                "height_cm": payload.height_cm, "weight_kg": payload.weight_kg, "bmi": bmi,
                "location": payload.location.strip(), "conditions": payload.conditions,
                "medications": payload.medications, "appetite": payload.appetite.strip(),
                "daily_routine": payload.daily_routine.strip(), "family_history": payload.family_history.strip(),
                "prescriptions": [item.model_dump() for item in payload.prescriptions],
                "profile_image": payload.profile_image, "updated_at": utc_now().isoformat(),
            }},
            upsert=True,
        )
        profile = database.profiles.find_one({"user_id": user_id})
    return profile_dict(profile) or {}


@app.post("/api/measurements", status_code=201)
def add_measurement(payload: MeasurementInput, user_id: CurrentUser) -> dict:
    values = payload.model_dump(exclude_none=True)
    if not values:
        raise HTTPException(status_code=422, detail="Add at least one measurement.")
    with connect_db() as database:
        measurement = insert_record(database, "measurements", {
            "user_id": user_id, **values, "recorded_at": utc_now().isoformat(),
        })
    return measurement


@app.get("/api/dashboard")
def dashboard(user_id: CurrentUser) -> dict:
    today = date.today().isoformat()
    with connect_db() as database:
        profile = database.profiles.find_one({"user_id": user_id})
        user = database.users.find_one({"id": user_id}, {"name": 1})
        measurements = list(database.measurements.find({"user_id": user_id}).sort("recorded_at", -1).limit(7))
        reminders = list(database.reminders.find({"user_id": user_id, "active": True}).sort("scheduled_time", 1))
        completed_ids = {
            item["reminder_id"] for item in database.reminder_completions.find(
                {"reminder_id": {"$in": [item["id"] for item in reminders]}, "completed_on": today},
                {"reminder_id": 1},
            )
        } if reminders else set()
        for reminder in reminders:
            reminder["completed_today"] = reminder["id"] in completed_ids
        patients_count = database.patients.count_documents({"user_id": user_id})
        dataset = database.dataset_summary.find_one({"id": 1})
    latest = document_dict(measurements[0]) if measurements else None
    flags = []
    if latest:
        if latest["fasting_glucose"] is not None and latest["fasting_glucose"] >= 126:
            flags.append("This fasting glucose reading is above a commonly used reference threshold. A clinician must interpret and confirm results.")
        if latest["systolic_bp"] is not None and latest["diastolic_bp"] is not None and (latest["systolic_bp"] >= 130 or latest["diastolic_bp"] >= 80):
            flags.append("This blood pressure reading is elevated under common adult guidance. Repeat it correctly and discuss it with a clinician.")
    return {
        "name": user["name"], "profile": profile_dict(profile), "latest_measurement": latest,
        "measurements": [document_dict(row) for row in measurements],
        "reminders": [document_dict(row) for row in reminders],
        "patients_count": patients_count, "dataset": document_dict(dataset), "reading_notes": flags,
    }


@app.get("/api/admin/users")
def admin_list_users(admin_id: CurrentAdmin) -> list[dict]:
    with connect_db() as database:
        insert_record(database, "admin_access_log", {
            "admin_user_id": admin_id, "action": "list_users", "accessed_at": utc_now().isoformat(),
        })
        users = database.users.find({}, {"_id": 0, "id": 1, "name": 1, "email": 1, "created_at": 1}).sort("created_at", -1)
    return list(users)


@app.get("/api/admin/users/{target_user_id}")
def admin_get_user(target_user_id: int, admin_id: CurrentAdmin) -> dict:
    with connect_db() as database:
        user = database.users.find_one(
            {"id": target_user_id}, {"_id": 0, "id": 1, "name": 1, "email": 1, "created_at": 1}
        )
        if user is None:
            raise HTTPException(status_code=404, detail="Account not found.")
        profile = database.profiles.find_one({"user_id": target_user_id})
        measurements = list(database.measurements.find({"user_id": target_user_id}).sort("recorded_at", -1))
        reminders = list(database.reminders.find({"user_id": target_user_id}).sort("scheduled_time", 1))
        patients = list(database.patients.find({"user_id": target_user_id}).sort("updated_at", -1))
        patient_records = []
        for patient_row in patients:
            patient = patient_dict(patient_row)
            visits = database.patient_visits.find(
                {"patient_id": patient_row["id"], "user_id": target_user_id}
            ).sort("visit_date", -1)
            patient["visits"] = [visit_dict(visit) for visit in visits]
            patient_records.append(patient)
        insert_record(database, "admin_access_log", {
            "admin_user_id": admin_id, "target_user_id": target_user_id,
            "action": "view_user_records", "accessed_at": utc_now().isoformat(),
        })
    return {
        "user": user,
        "profile": profile_dict(profile),
        "measurements": [document_dict(row) for row in measurements],
        "reminders": [document_dict(row) for row in reminders],
        "patients": patient_records,
    }


# ==========================================
# PATIENT MANAGEMENT ENDPOINTS
# ==========================================

@app.get("/api/patients")
def list_patients(user_id: CurrentUser, q: str | None = Query(default=None)) -> list[dict]:
    query = {"user_id": user_id}
    if q and q.strip():
        pattern = re.escape(q.strip())
        query["$or"] = [
            {field: {"$regex": pattern, "$options": "i"}}
            for field in ("name", "patient_id", "phone", "chronic_conditions")
        ]
    with connect_db() as database:
        rows = list(database.patients.find(query).sort("updated_at", -1))
        result = []
        for row in rows:
            visits = list(database.patient_visits.find({"patient_id": row["id"]}).sort("visit_date", -1).limit(1))
            patient = patient_dict(row)
            patient["visit_count"] = database.patient_visits.count_documents({"patient_id": row["id"]})
            patient["last_visit_date"] = visits[0]["visit_date"] if visits else None
            result.append(patient)
    return result


@app.post("/api/patients", status_code=201)
def create_patient(payload: PatientInput, user_id: CurrentUser) -> dict:
    now = utc_now().isoformat()
    with connect_db() as database:
        pid = payload.patient_id.strip() if payload.patient_id and payload.patient_id.strip() else None
        if not pid:
            count = database.patients.count_documents({})
            candidate_id = f"PAT-{1001 + count}"
            while database.patients.find_one({"patient_id": candidate_id}):
                count += 1
                candidate_id = f"PAT-{1001 + count}"
            pid = candidate_id

        try:
            row = insert_record(database, "patients", {
                "user_id": user_id, "patient_id": pid, "name": payload.name.strip(), "age": payload.age,
                "gender": payload.gender.strip(), "phone": payload.phone.strip(),
                "email": payload.email.strip().lower(), "blood_group": payload.blood_group.strip(),
                "address": payload.address.strip(), "emergency_contact": payload.emergency_contact.strip(),
                "chronic_conditions": payload.chronic_conditions, "allergies": payload.allergies,
                "current_medications": payload.current_medications, "notes": payload.notes.strip(),
                "created_at": now, "updated_at": now,
            })
        except DuplicateKeyError as error:
            raise HTTPException(status_code=409, detail=f"A patient with ID '{pid}' already exists.") from error

    p = patient_dict(row)
    p["visit_count"] = 0
    p["last_visit_date"] = None
    p["visits"] = []
    return p


@app.get("/api/patients/{patient_id}")
def get_patient(patient_id: str, user_id: CurrentUser) -> dict:
    with connect_db() as database:
        row = database.patients.find_one(patient_query(patient_id, user_id))
        if row is None:
            raise HTTPException(status_code=404, detail="Patient not found.")
        visits = list(database.patient_visits.find({"patient_id": row["id"]}).sort([("visit_date", -1), ("id", -1)]))

    patient = patient_dict(row)
    patient["visits"] = [visit_dict(v) for v in visits]
    patient["visit_count"] = len(visits)
    patient["last_visit_date"] = visits[0]["visit_date"] if visits else None
    return patient


@app.put("/api/patients/{patient_id}")
def update_patient(patient_id: str, payload: PatientInput, user_id: CurrentUser) -> dict:
    now = utc_now().isoformat()
    with connect_db() as database:
        existing = database.patients.find_one(patient_query(patient_id, user_id))
        if existing is None:
            raise HTTPException(status_code=404, detail="Patient not found.")

        target_pid = payload.patient_id.strip() if payload.patient_id and payload.patient_id.strip() else existing["patient_id"]
        try:
            database.patients.update_one({"id": existing["id"]}, {"$set": {
                "patient_id": target_pid, "name": payload.name.strip(), "age": payload.age,
                "gender": payload.gender.strip(), "phone": payload.phone.strip(),
                "email": payload.email.strip().lower(), "blood_group": payload.blood_group.strip(),
                "address": payload.address.strip(), "emergency_contact": payload.emergency_contact.strip(),
                "chronic_conditions": payload.chronic_conditions, "allergies": payload.allergies,
                "current_medications": payload.current_medications, "notes": payload.notes.strip(),
                "updated_at": now,
            }})
        except DuplicateKeyError as error:
            raise HTTPException(status_code=409, detail=f"A patient with ID '{target_pid}' already exists.") from error

        row = database.patients.find_one({"id": existing["id"]})
        visits = list(database.patient_visits.find({"patient_id": existing["id"]}).sort([("visit_date", -1), ("id", -1)]))

    p = patient_dict(row)
    p["visits"] = [visit_dict(v) for v in visits]
    p["visit_count"] = len(visits)
    p["last_visit_date"] = visits[0]["visit_date"] if visits else None
    return p


@app.delete("/api/patients/{patient_id}", status_code=204)
def delete_patient(patient_id: str, user_id: CurrentUser) -> None:
    with connect_db() as database:
        patient = database.patients.find_one(patient_query(patient_id, user_id), {"id": 1})
        if patient is None:
            raise HTTPException(status_code=404, detail="Patient not found.")
        database.patient_visits.delete_many({"patient_id": patient["id"]})
        database.patients.delete_one({"id": patient["id"], "user_id": user_id})


@app.post("/api/patients/{patient_id}/visits", status_code=201)
def add_patient_visit(patient_id: str, payload: VisitInput, user_id: CurrentUser) -> dict:
    now = utc_now().isoformat()
    visit_date = payload.visit_date.strip() if payload.visit_date and payload.visit_date.strip() else date.today().isoformat()
    with connect_db() as database:
        patient = database.patients.find_one(patient_query(patient_id, user_id), {"id": 1})
        if patient is None:
            raise HTTPException(status_code=404, detail="Patient not found.")

        row = insert_record(database, "patient_visits", {
            "patient_id": patient["id"], "user_id": user_id, "visit_date": visit_date,
            "chief_complaint": payload.chief_complaint.strip(), "diagnosis": payload.diagnosis.strip(),
            "systolic_bp": payload.systolic_bp, "diastolic_bp": payload.diastolic_bp,
            "fasting_glucose": payload.fasting_glucose, "heart_rate": payload.heart_rate,
            "temperature": payload.temperature, "weight_kg": payload.weight_kg,
            "prescriptions": payload.prescriptions, "clinical_notes": payload.clinical_notes.strip(),
            "next_followup": payload.next_followup, "created_at": now,
        })
        database.patients.update_one({"id": patient["id"]}, {"$set": {"updated_at": now}})

    return visit_dict(row)


@app.put("/api/patients/{patient_id}/visits/{visit_id}")
def update_patient_visit(patient_id: str, visit_id: int, payload: VisitInput, user_id: CurrentUser) -> dict:
    visit_date = payload.visit_date.strip() if payload.visit_date and payload.visit_date.strip() else date.today().isoformat()
    with connect_db() as database:
        patient = database.patients.find_one(patient_query(patient_id, user_id), {"id": 1})
        if patient is None:
            raise HTTPException(status_code=404, detail="Patient not found.")

        result = database.patient_visits.update_one(
            {"id": visit_id, "patient_id": patient["id"], "user_id": user_id},
            {"$set": {
                "visit_date": visit_date, "chief_complaint": payload.chief_complaint.strip(),
                "diagnosis": payload.diagnosis.strip(), "systolic_bp": payload.systolic_bp,
                "diastolic_bp": payload.diastolic_bp, "fasting_glucose": payload.fasting_glucose,
                "heart_rate": payload.heart_rate, "temperature": payload.temperature,
                "weight_kg": payload.weight_kg, "prescriptions": payload.prescriptions,
                "clinical_notes": payload.clinical_notes.strip(), "next_followup": payload.next_followup,
            }},
        )
        if result.matched_count == 0:
            raise HTTPException(status_code=404, detail="Visit record not found.")

        database.patients.update_one({"id": patient["id"]}, {"$set": {"updated_at": utc_now().isoformat()}})
        row = database.patient_visits.find_one({"id": visit_id})

    return visit_dict(row)


@app.delete("/api/patients/{patient_id}/visits/{visit_id}", status_code=204)
def delete_patient_visit(patient_id: str, visit_id: int, user_id: CurrentUser) -> None:
    with connect_db() as database:
        patient = database.patients.find_one(patient_query(patient_id, user_id), {"id": 1})
        if patient is None:
            raise HTTPException(status_code=404, detail="Patient not found.")

        result = database.patient_visits.delete_one(
            {"id": visit_id, "patient_id": patient["id"], "user_id": user_id}
        )
        if result.deleted_count == 0:
            raise HTTPException(status_code=404, detail="Visit record not found.")


# ==========================================
# REMINDERS ENDPOINTS
# ==========================================

@app.get("/api/reminders")
def list_reminders(user_id: CurrentUser) -> list[dict]:
    today = date.today().isoformat()
    with connect_db() as database:
        rows = list(database.reminders.find({"user_id": user_id, "active": True}).sort("scheduled_time", 1))
        completed_ids = {
            item["reminder_id"] for item in database.reminder_completions.find(
                {"reminder_id": {"$in": [row["id"] for row in rows]}, "completed_on": today},
                {"reminder_id": 1},
            )
        } if rows else set()
        for row in rows:
            row["completed_today"] = row["id"] in completed_ids
    return [document_dict(row) for row in rows]


@app.post("/api/reminders", status_code=201)
def add_reminder(payload: ReminderInput, user_id: CurrentUser) -> dict:
    with connect_db() as connection:
        row = insert_record(connection, "reminders", {
            "user_id": user_id, "title": payload.title.strip(), "scheduled_time": payload.scheduled_time,
            "instruction": payload.instruction.strip(), "active": True,
            "created_at": utc_now().isoformat(),
        })
    return row


@app.post("/api/reminders/{reminder_id}/complete", status_code=204)
def complete_reminder(reminder_id: int, user_id: CurrentUser) -> None:
    with connect_db() as database:
        reminder = database.reminders.find_one({"id": reminder_id, "user_id": user_id, "active": True})
        if reminder is None:
            raise HTTPException(status_code=404, detail="Reminder not found.")
        database.reminder_completions.update_one(
            {"reminder_id": reminder_id, "completed_on": date.today().isoformat()},
            {"$setOnInsert": {"user_id": user_id}},
            upsert=True,
        )


@app.post("/api/prescription-completions", status_code=201)
def complete_prescription_intake(
    payload: PrescriptionCompletionInput,
    user_id: CurrentUser,
) -> dict:
    try:
        completed_on = date.fromisoformat(payload.completed_on)
    except ValueError as error:
        raise HTTPException(status_code=422, detail="Use a valid local completion date.") from error
    if abs((completed_on - date.today()).days) > 1:
        raise HTTPException(status_code=422, detail="Completion date must be today in your local timezone.")

    with connect_db() as database:
        profile = database.profiles.find_one({"user_id": user_id}, {"prescriptions": 1})
        prescriptions = profile.get("prescriptions", []) if profile else []
        valid_intake = any(
            item.get("id") == payload.prescription_id
            and payload.scheduled_time in item.get("intake_times", [])
            for item in prescriptions
        )
        if not valid_intake:
            raise HTTPException(status_code=404, detail="Prescription schedule not found.")
        database.prescription_completions.update_one(
            {
                "user_id": user_id,
                "prescription_id": payload.prescription_id,
                "scheduled_time": payload.scheduled_time,
                "completed_on": payload.completed_on,
            },
            {"$setOnInsert": {
                "id": next_id(database, "prescription_completions"),
                "created_at": utc_now().isoformat(),
            }},
            upsert=True,
        )
    return {"completed": True, "completed_on": payload.completed_on}


@app.delete("/api/reminders/{reminder_id}", status_code=204)
def delete_reminder(reminder_id: int, user_id: CurrentUser) -> None:
    with connect_db() as database:
        result = database.reminders.delete_one({"id": reminder_id, "user_id": user_id})
        if result.deleted_count == 0:
            raise HTTPException(status_code=404, detail="Reminder not found.")


@app.get("/{path:path}")
def frontend_fallback(path: str) -> FileResponse:
    file_path = (STATIC_DIR / path).resolve()
    if file_path.is_file() and STATIC_DIR in file_path.parents:
        return FileResponse(file_path)
    return FileResponse(STATIC_DIR / "index.html")