from __future__ import annotations

import os
from contextlib import contextmanager
from pathlib import Path
from typing import Iterator

from dotenv import load_dotenv
from pymongo import MongoClient, ReturnDocument
from pymongo.database import Database


ROOT = Path(__file__).resolve().parent.parent
load_dotenv(ROOT / ".env")

MONGODB_URI = os.environ.get("MONGODB_URI", "").strip()
MONGODB_DATABASE = os.environ.get("MONGODB_DATABASE", "").strip()
_client: MongoClient | None = None


def get_client() -> MongoClient:
    global _client
    if not MONGODB_URI:
        raise RuntimeError(
            "MONGODB_URI is not configured. Add it to the environment or the project .env file."
        )
    if _client is None:
        _client = MongoClient(MONGODB_URI)
    return _client


def get_database() -> Database:
    client = get_client()
    if MONGODB_DATABASE:
        return client[MONGODB_DATABASE]
    return client.get_default_database("beluga")


@contextmanager
def connect_db() -> Iterator[Database]:
    yield get_database()


def initialize_database() -> None:
    client = get_client()
    client.admin.command("ping")
    database = get_database()
    database.users.create_index("email", unique=True)
    database.profiles.create_index("user_id", unique=True)
    database.sessions.create_index("token_hash", unique=True)
    database.measurements.create_index([("user_id", 1), ("recorded_at", -1)])
    database.reminders.create_index([("user_id", 1), ("active", 1), ("scheduled_time", 1)])
    database.dataset_summary.create_index("id", unique=True)
    database.patients.create_index("patient_id", unique=True)
    database.patients.create_index([("user_id", 1), ("updated_at", -1)])
    database.patient_visits.create_index([("patient_id", 1), ("visit_date", -1), ("id", -1)])
    database.admin_access_log.create_index([("admin_user_id", 1), ("accessed_at", -1)])
    database.reminder_completions.create_index(
        [("reminder_id", 1), ("completed_on", 1)], unique=True
    )
    database.prescription_completions.create_index(
        [("user_id", 1), ("prescription_id", 1), ("scheduled_time", 1), ("completed_on", 1)],
        unique=True,
    )


def next_id(database: Database, collection: str) -> int:
    counter = database.counters.find_one_and_update(
        {"_id": collection},
        {"$inc": {"value": 1}},
        upsert=True,
        return_document=ReturnDocument.AFTER,
    )
    return int(counter["value"])


def close_client() -> None:
    global _client
    if _client is not None:
        _client.close()
        _client = None