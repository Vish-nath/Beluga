# Beluga Health MongoDB Collections

The API reads `MONGODB_URI` and optional `MONGODB_DATABASE` from the environment or project `.env` file. The database name in the URI is used when present; otherwise the default is `beluga`. Startup verifies connectivity and creates the indexes listed in [app/database.py](../app/database.py).

## Collections

| Collection | Contents | Important indexes |
| --- | --- | --- |
| `users` | Accounts and administrator flags | Unique `email` |
| `profiles` | Health profile, prescriptions, and preferences | Unique `user_id` |
| `sessions` | Hashed bearer tokens and expiry | Unique `token_hash` |
| `measurements` | User health measurements | `user_id`, `recorded_at` |
| `reminders` | User reminders | `user_id`, `active`, `scheduled_time` |
| `reminder_completions` | Daily reminder completion | Unique `reminder_id`, `completed_on` |
| `prescription_completions` | Completed prescription intakes | Unique `user_id`, `prescription_id`, `scheduled_time`, `completed_on` |
| `dataset_summary` | Imported aggregate dataset statistics | Unique `id` (singleton value `1`) |
| `patients` | Patient demographics and clinical notes | Unique `patient_id`; `user_id`, `updated_at` |
| `patient_visits` | Patient visit measurements and notes | `patient_id`, `visit_date`, `id` |
| `admin_access_log` | Administrative access audit records | `admin_user_id`, `accessed_at` |
| `counters` | Atomic numeric ID counters used by the API | MongoDB `_id` |

Documents retain numeric `id` values for compatibility with existing clients. Related documents refer to those IDs; the API explicitly removes patient visits when deleting a patient because MongoDB does not enforce relational foreign keys.

## Setup

Copy `.env.example` to `.env`, set `MONGODB_URI` to the connection string supplied by MongoDB, and set `MONGODB_DATABASE` if you want a name other than `beluga`. Never commit `.env` or put credentials directly in source code. Run `py scripts/inspect_and_setup_db.py` to verify the connection and initialize indexes.

The former SQLite schema is retained in [schema.sql](schema.sql) for historical reference only. Existing SQLite data is not imported automatically.