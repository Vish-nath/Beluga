-- Legacy SQLite schema; the application now uses MongoDB.
-- MongoDB collections and indexes are initialized by app/database.py.
-- This file is retained only as a historical reference.
-- Beluga Health Database Schema
-- SQLite Database: healthbot.sqlite3
-- Generated automatically

PRAGMA foreign_keys = ON;

-- TABLE: admin_access_log
CREATE TABLE admin_access_log (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                admin_user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
                target_user_id INTEGER REFERENCES users(id) ON DELETE SET NULL,
                action TEXT NOT NULL,
                accessed_at TEXT NOT NULL
            );

-- TABLE: dataset_summary
CREATE TABLE dataset_summary (
                id INTEGER PRIMARY KEY CHECK (id = 1),
                record_count INTEGER NOT NULL,
                diabetes_count INTEGER NOT NULL,
                hypertension_count INTEGER NOT NULL,
                average_age REAL NOT NULL,
                average_bmi REAL NOT NULL,
                imported_at TEXT NOT NULL
            );

-- TABLE: measurements
CREATE TABLE measurements (
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

-- TABLE: patient_visits
CREATE TABLE patient_visits (
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

-- TABLE: patients
CREATE TABLE patients (
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

-- TABLE: prescription_completions
CREATE TABLE prescription_completions (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
                prescription_id TEXT NOT NULL,
                scheduled_time TEXT NOT NULL,
                completed_on TEXT NOT NULL,
                created_at TEXT NOT NULL,
                UNIQUE(user_id, prescription_id, scheduled_time, completed_on)
            );

-- TABLE: profiles
CREATE TABLE profiles (
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
            , appetite TEXT NOT NULL DEFAULT '', daily_routine TEXT NOT NULL DEFAULT '', family_history TEXT NOT NULL DEFAULT '', prescriptions TEXT NOT NULL DEFAULT '[]', profile_image TEXT NOT NULL DEFAULT '');

-- TABLE: reminder_completions
CREATE TABLE reminder_completions (
                reminder_id INTEGER NOT NULL REFERENCES reminders(id) ON DELETE CASCADE,
                completed_on TEXT NOT NULL,
                PRIMARY KEY (reminder_id, completed_on)
            );

-- TABLE: reminders
CREATE TABLE reminders (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
                title TEXT NOT NULL,
                scheduled_time TEXT NOT NULL,
                instruction TEXT NOT NULL DEFAULT '',
                active INTEGER NOT NULL DEFAULT 1,
                created_at TEXT NOT NULL
            );

-- TABLE: sessions
CREATE TABLE sessions (
                token_hash TEXT PRIMARY KEY,
                user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
                expires_at TEXT NOT NULL
            );

-- TABLE: users
CREATE TABLE users (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                name TEXT NOT NULL,
                email TEXT NOT NULL UNIQUE COLLATE NOCASE,
                password_hash TEXT NOT NULL,
                password_salt TEXT NOT NULL,
                created_at TEXT NOT NULL
            , is_admin INTEGER NOT NULL DEFAULT 0);

-- INDEX: idx_patients_user
CREATE INDEX idx_patients_user ON patients(user_id);

-- INDEX: idx_visits_patient
CREATE INDEX idx_visits_patient ON patient_visits(patient_id);
