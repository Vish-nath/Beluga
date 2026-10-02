from __future__ import annotations

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from app.main import connect_db, initialize_database


def main() -> None:
    parser = argparse.ArgumentParser(description="Make one existing Beluga account the app administrator.")
    parser.add_argument("email", help="Email address of the account to promote")
    email = parser.parse_args().email.strip().lower()

    initialize_database()
    with connect_db() as connection:
        user = connection.execute("SELECT id FROM users WHERE email = ?", (email,)).fetchone()
        if user is None:
            parser.error("No account exists for that email. Create the account in the app first.")
        connection.execute("UPDATE users SET is_admin = 0")
        connection.execute("UPDATE users SET is_admin = 1 WHERE id = ?", (user["id"],))

    print(f"Administrator role assigned to {email}.")


if __name__ == "__main__":
    main()