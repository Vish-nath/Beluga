from __future__ import annotations

import plistlib
import subprocess
import sys
import xml.etree.ElementTree as ElementTree
from pathlib import Path


ROOT = Path(__file__).resolve().parent
ANDROID_NAMESPACE = "http://schemas.android.com/apk/res/android"


def prepare_android_debug_networking() -> None:
    manifest_dir = ROOT / "android" / "app" / "src" / "debug"
    manifest_dir.mkdir(parents=True, exist_ok=True)
    manifest = ElementTree.Element("manifest")
    application = ElementTree.SubElement(manifest, "application")
    application.set(f"{{{ANDROID_NAMESPACE}}}usesCleartextTraffic", "true")
    ElementTree.register_namespace("android", ANDROID_NAMESPACE)
    ElementTree.ElementTree(manifest).write(
        manifest_dir / "AndroidManifest.xml",
        encoding="utf-8",
        xml_declaration=True,
    )


def prepare_macos_entitlements() -> None:
    entitlement_files = (
        ROOT / "macos" / "Runner" / "DebugProfile.entitlements",
        ROOT / "macos" / "Runner" / "Release.entitlements",
    )
    for entitlement_file in entitlement_files:
        with entitlement_file.open("rb") as source:
            entitlements = plistlib.load(source)
        entitlements["com.apple.security.network.client"] = True
        entitlements["keychain-access-groups"] = [
            "$(AppIdentifierPrefix)$(PRODUCT_BUNDLE_IDENTIFIER)"
        ]
        with entitlement_file.open("wb") as destination:
            plistlib.dump(entitlements, destination, sort_keys=False)


def main() -> None:
    main_file = ROOT / "lib" / "main.dart"
    pubspec_file = ROOT / "pubspec.yaml"
    saved_main = main_file.read_bytes()
    saved_pubspec = pubspec_file.read_bytes()
    try:
        subprocess.run(
            [
                "flutter",
                "create",
                "--platforms=android,macos",
                "--org",
                "edu.vtu",
                "--project-name",
                "beluga_health",
                "--no-pub",
                ".",
            ],
            cwd=ROOT,
            check=True,
        )
    finally:
        main_file.write_bytes(saved_main)
        pubspec_file.write_bytes(saved_pubspec)

    prepare_android_debug_networking()
    prepare_macos_entitlements()
    subprocess.run(["flutter", "pub", "get"], cwd=ROOT, check=True)
    print("Flutter Android and macOS runners are ready.")


if __name__ == "__main__":
    try:
        main()
    except FileNotFoundError as error:
        print("Flutter must be installed and available on PATH.", file=sys.stderr)
        raise SystemExit(1) from error
    except subprocess.CalledProcessError as error:
        raise SystemExit(error.returncode) from error