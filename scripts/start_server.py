from __future__ import annotations

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
    print("=" * 68)
    print("           BELUGA HEALTH - LOCAL SERVER & DATABASE")
    print("=" * 68)
    print("\nStarting Beluga API server on all network interfaces (0.0.0.0:8000)...")

    local_ips = get_local_ips()
    print("\n--- HOW TO CONNECT YOUR ANDROID APK ---")
    if local_ips:
        print("1. [Same Wi-Fi Network]:")
        for ip in local_ips:
            print(f"   Enter this Server URL in the APK: http://{ip}:8000/api")
        print("   (Ensure your phone and this PC are on the same Wi-Fi network,")
        print("    and allow Python through Windows Firewall if prompted.)")
    else:
        print("1. [Same Wi-Fi Network]: Connect your PC and phone to Wi-Fi and use your PC's IP address.")

    print("\n2. [Anywhere on the Internet / Cellular Data] (Recommended for public APKs):")
    print("   Run a free secure tunnel in another terminal:")
    print("   - Using Cloudflare Tunnel:  cloudflared tunnel --url http://localhost:8000")
    print("   - Using ngrok:              ngrok http 8000")
    print("   Then enter the generated HTTPS URL in the APK, e.g.:")
    print("   https://xxxx.trycloudflare.com/api  or  https://xxxx.ngrok-free.app/api")

    print("\n3. [Android Emulator on this PC]:")
    print("   Default URL: http://10.0.2.2:8000/api")

    print("\n4. [Web Browser on this PC]:")
    print("   Open: http://localhost:8000")
    print("=" * 68)
    print("\nServer logs:\n")

    root = Path(__file__).resolve().parents[1]
    python_exe = sys.executable
    try:
        subprocess.run(
            [python_exe, "-m", "uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000", "--reload"],
            cwd=root,
            check=True,
        )
    except KeyboardInterrupt:
        print("\nBeluga Health Server stopped.")


if __name__ == "__main__":
    main()
