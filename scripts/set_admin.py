from __future__ import annotations

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from app.database import connect_db, initialize_database


def main() -> None:
    parser = argparse.ArgumentParser(description="Make one existing Beluga account the app administrator.")
    parser.add_argument("email", help="Email address of the account to promote")
    email = parser.parse_args().email.strip().lower()

    initialize_database()
    with connect_db() as database:
        user = database.users.find_one({"email": email}, {"id": 1})
        if user is None:
            parser.error("No account exists for that email. Create the account in the app first.")
        database.users.update_many({}, {"$set": {"is_admin": False}})
        database.users.update_one({"id": user["id"]}, {"$set": {"is_admin": True}})

    print(f"Administrator role assigned to {email}.")


if __name__ == "__main__":
    main()