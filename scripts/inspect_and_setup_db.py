from __future__ import annotations

import sys
from pathlib import Path

# Add project root to sys.path
ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from app.database import connect_db, initialize_database


def main() -> None:
    initialize_database()
    with connect_db() as database:
        print(f"MongoDB database: {database.name}")
        print("Collections:")
        for name in sorted(database.list_collection_names()):
            print(f"  - {name}: {database[name].count_documents({})} documents")


if __name__ == "__main__":
    main()
