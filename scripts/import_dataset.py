from __future__ import annotations

import argparse
import csv
import sys
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from app.database import connect_db, initialize_database


REQUIRED_COLUMNS = {
    "Age", "BMI", "Label_Diabetes", "Label_Hypertension",
}


def main() -> None:
    parser = argparse.ArgumentParser(description="Import aggregate statistics from the sample health CSV.")
    parser.add_argument("csv_path", type=Path)
    args = parser.parse_args()

    with args.csv_path.open("r", newline="", encoding="utf-8-sig") as source:
        reader = csv.DictReader(source)
        columns = set(reader.fieldnames or [])
        missing = REQUIRED_COLUMNS - columns
        if missing:
            parser.error(f"CSV is missing required columns: {', '.join(sorted(missing))}")
        records = list(reader)

    if not records:
        parser.error("CSV contains no patient records.")

    try:
        ages = [float(row["Age"]) for row in records]
        bmis = [float(row["BMI"]) for row in records]
        diabetes_count = sum(int(row["Label_Diabetes"]) for row in records)
        hypertension_count = sum(int(row["Label_Hypertension"]) for row in records)
        if any(value not in (0, 1) for row in records for value in (int(row["Label_Diabetes"]), int(row["Label_Hypertension"]))):
            raise ValueError("Labels must be 0 or 1.")
    except (TypeError, ValueError) as error:
        parser.error(f"CSV contains invalid numeric values: {error}")

    initialize_database()
    with connect_db() as database:
        database.dataset_summary.replace_one(
            {"id": 1},
            {
                "id": 1,
                "record_count": len(records),
                "diabetes_count": diabetes_count,
                "hypertension_count": hypertension_count,
                "average_age": sum(ages) / len(ages),
                "average_bmi": sum(bmis) / len(bmis),
                "imported_at": datetime.now(timezone.utc).isoformat(),
            },
            upsert=True,
        )

    print(f"Imported aggregate summary for {len(records)} records; no individual rows were stored.")


if __name__ == "__main__":
    main()