from __future__ import annotations

import plistlib
import subprocess
import sys
import xml.etree.ElementTree as ElementTree
from pathlib import Path


ROOT = Path(__file__).resolve().parent
ANDROID_NAMESPACE = "http://schemas.android.com/apk/res/android"


def prepare_android_networking() -> None:
    # 1. Update debug manifest
    debug_dir = ROOT / "android" / "app" / "src" / "debug"
    debug_dir.mkdir(parents=True, exist_ok=True)
    manifest = ElementTree.Element("manifest")
    application = ElementTree.SubElement(manifest, "application")
    application.set(f"{{{ANDROID_NAMESPACE}}}usesCleartextTraffic", "true")
    ElementTree.register_namespace("android", ANDROID_NAMESPACE)
    ElementTree.ElementTree(manifest).write(
        debug_dir / "AndroidManifest.xml",
        encoding="utf-8",
        xml_declaration=True,
    )

    # 2. Update main manifest for release builds
    main_manifest = ROOT / "android" / "app" / "src" / "main" / "AndroidManifest.xml"
    if main_manifest.exists():
        ElementTree.register_namespace("android", ANDROID_NAMESPACE)
        tree = ElementTree.parse(main_manifest)
        root = tree.getroot()

        # Add permissions if not present
        existing_permissions = {elem.attrib.get(f"{{{ANDROID_NAMESPACE}}}name") for elem in root.findall("uses-permission")}
        for perm in ("android.permission.INTERNET", "android.permission.ACCESS_NETWORK_STATE"):
            if perm not in existing_permissions:
                p_elem = ElementTree.SubElement(root, "uses-permission")
                p_elem.set(f"{{{ANDROID_NAMESPACE}}}name", perm)

        # Ensure application has usesCleartextTraffic="true" for connecting to local IP / HTTP servers
        app_elem = root.find("application")
        if app_elem is not None:
            app_elem.set(f"{{{ANDROID_NAMESPACE}}}usesCleartextTraffic", "true")

        tree.write(main_manifest, encoding="utf-8", xml_declaration=True)


def prepare_macos_entitlements() -> None:
    entitlement_files = (
        ROOT / "macos" / "Runner" / "DebugProfile.entitlements",
        ROOT / "macos" / "Runner" / "Release.entitlements",
    )
    for entitlement_file in entitlement_files:
        if entitlement_file.exists():
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

    prepare_android_networking()
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