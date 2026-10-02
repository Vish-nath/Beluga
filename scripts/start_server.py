from __future__ import annotations

import argparse
import socket
import subprocess
import sys
from pathlib import Path


def get_local_ips() -> list[str]:
    ips = []
    try:
        hostname = socket.gethostname()
        for ip in socket.gethostbyname_ex(hostname)[2]:
            if not ip.startswith("127."):
                ips.append(ip)
    except Exception:
        pass
    return ips


def main() -> None:
    parser = argparse.ArgumentParser(description="Run the Beluga API server for local development.")
    parser.add_argument(
        "--host",
        default="0.0.0.0",
        help="Bind address; use 127.0.0.1 when serving through a local HTTPS tunnel.",
    )
    parser.add_argument("--reload", action="store_true", help="Enable development auto-reload.")
    args = parser.parse_args()

    print("=" * 68)
    print("           BELUGA HEALTH - LOCAL SERVER & DATABASE")
    print("=" * 68)
    print(f"\nStarting the API server on {args.host}:8000...")

    if args.host in {"127.0.0.1", "localhost"}:
        print("Keep this server bound to localhost when using a public HTTPS tunnel.")
        print("Do not configure router port forwarding for port 8000.")
    else:
        print("Use only on trusted networks; allow Python through Windows Firewall on private networks only.")
        print("Same-Wi-Fi clients can use one of these addresses:")
        for ip in get_local_ips():
            print(f"   http://{ip}:8000/api")
    print("\nAndroid emulator URL: http://10.0.2.2:8000/api")
    print("Web browser on this PC: http://localhost:8000")
    print("=" * 68)
    print("\nServer logs:\n")

    root = Path(__file__).resolve().parents[1]
    command = [
        sys.executable,
        "-m",
        "uvicorn",
        "app.main:app",
        "--host",
        args.host,
        "--port",
        "8000",
    ]
    if args.reload:
        command.append("--reload")
    try:
        subprocess.run(command, cwd=root, check=True)
    except KeyboardInterrupt:
        print("\nBeluga Health Server stopped.")


if __name__ == "__main__":
    main()
