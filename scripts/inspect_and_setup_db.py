from __future__ import annotations

import json
import sqlite3
import sys
from pathlib import Path

# Add project root to sys.path
ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from app.main import DATABASE_PATH, initialize_database


def inspect_database() -> dict:
    conn = sqlite3.connect(DATABASE_PATH)
    conn.row_factory = sqlite3.Row
    cursor = conn.cursor()

    cursor.execute("SELECT name, sql FROM sqlite_master WHERE type='table' ORDER BY name;")
    tables = cursor.fetchall()

    result = {}
    for table_row in tables:
        tname = table_row["name"]
        if tname == "sqlite_sequence":
            continue
        cursor.execute(f"PRAGMA table_info('{tname}');")
        cols = [dict(c) for c in cursor.fetchall()]

        cursor.execute(f"PRAGMA foreign_key_list('{tname}');")
        fks = [dict(f) for f in cursor.fetchall()]

        cursor.execute(f"PRAGMA index_list('{tname}');")
        idxs = [dict(i) for i in cursor.fetchall()]

        cursor.execute(f"SELECT COUNT(*) FROM '{tname}';")
        count = cursor.fetchone()[0]

        result[tname] = {
            "sql": table_row["sql"],
            "row_count": count,
            "columns": cols,
            "foreign_keys": fks,
            "indexes": idxs,
        }

    conn.close()
    return result


def export_schema_sql(dest_path: Path) -> None:
    conn = sqlite3.connect(DATABASE_PATH)
    cursor = conn.cursor()
    cursor.execute("SELECT type, name, sql FROM sqlite_master WHERE sql IS NOT NULL AND name NOT LIKE 'sqlite_%' ORDER BY type DESC, name ASC;")
    items = cursor.fetchall()
    conn.close()

    lines = [
        "-- Beluga Health Database Schema",
        f"-- SQLite Database: {DATABASE_PATH.name}",
        "-- Generated automatically\n",
        "PRAGMA foreign_keys = ON;\n",
    ]

    for item_type, name, sql in items:
        clean_sql = sql.strip()
        if not clean_sql.endswith(";"):
            clean_sql += ";"
        lines.append(f"-- {item_type.upper()}: {name}")
        lines.append(clean_sql + "\n")

    dest_path.write_text("\n".join(lines), encoding="utf-8")
    print(f"Exported schema definition to {dest_path}")


def main() -> None:
    print(f"Database path: {DATABASE_PATH}")
    print("\n--- BEFORE INITIALIZE_DATABASE ---")
    before = inspect_database()
    print(f"Tables count: {len(before)}")
    for name, info in before.items():
        print(f"  - {name} ({info['row_count']} rows, {len(info['columns'])} cols)")

    print("\nRunning initialize_database()...")
    initialize_database()

    print("\n--- AFTER INITIALIZE_DATABASE ---")
    after = inspect_database()
    print(f"Tables count: {len(after)}")
    for name, info in after.items():
        print(f"  - {name} ({info['row_count']} rows, {len(info['columns'])} cols)")
        col_names = [c["name"] for c in info["columns"]]
        print(f"    Columns: {', '.join(col_names)}")

    export_schema_sql(ROOT / "data" / "schema.sql")


if __name__ == "__main__":
    main()
