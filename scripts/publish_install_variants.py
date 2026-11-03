#!/usr/bin/env python3
"""Publish one real Aukkhor iOS app: main app plus keyboard extension.

Do not expose installation probes as normal apps or consume another App ID.
The IPA remains unsigned and requires valid provisioning for both identifiers.
"""
import argparse
import json
import plistlib
import zipfile
from datetime import datetime, timezone
from pathlib import Path

IPA = "Aukkhor-unsigned.ipa"
HOST_ID = "dev.soum91.aukkhor"
KEYBOARD_ID = "dev.soum91.aukkhor.keyboard"

def synchronize_latest_version(main_app, note):
    """Keep legacy single-version installers on the newest verified IPA."""
    latest = main_app["versions"][0]
    main_app.update({
        "version": latest["version"],
        "buildVersion": latest["buildVersion"],
        "downloadURL": latest["downloadURL"],
        "size": latest["size"],
        "minOSVersion": latest["minOSVersion"],
        "versionDate": latest["date"],
        "versionDescription": note,
    })

def inspect(path):
    if not path.is_file() or path.stat().st_size < 100_000:
        raise SystemExit(f"Missing or unexpectedly small IPA: {path}")
    with zipfile.ZipFile(path) as archive:
        names = set(archive.namelist())
        host_path = "Payload/Aukkhor.app/Info.plist"
        keyboard_path = "Payload/Aukkhor.app/PlugIns/AukkhorKeyboard.appex/Info.plist"
        if host_path not in names or keyboard_path not in names:
            raise SystemExit("Host or keyboard extension missing from IPA")
        if any("/AukkhorShare.appex/" in p for p in names):
            raise SystemExit("Unexpected Share extension in IPA")
        app = plistlib.loads(archive.read(host_path))
        keyboard = plistlib.loads(archive.read(keyboard_path))
        if app.get("CFBundleIdentifier") != HOST_ID:
            raise SystemExit("Wrong main bundle ID")
        if keyboard.get("CFBundleIdentifier") != KEYBOARD_ID:
            raise SystemExit("Wrong keyboard bundle ID")
        if keyboard.get("NSExtension", {}).get("NSExtensionPointIdentifier") != "com.apple.keyboard-service":
            raise SystemExit("Not a valid keyboard extension")
        for label, info in (("main", app), ("keyboard", keyboard)):
            if not str(info.get("CFBundleDisplayName", "")).strip():
                raise SystemExit(f"Missing display name in {label}")
        print("Verified host + keyboard extension only; no Share extension")

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--build", required=True, type=int)
    parser.add_argument("--directory", required=True, type=Path)
    parser.add_argument("--mode", required=True, choices=("release", "direct"))
    args = parser.parse_args()
    version = f"0.2.0.{args.build}"
    marketing_version = "0.2.0"
    inspect(args.directory / IPA)
    prefix = (
        f"https://github.com/soum91/aukkhor/releases/download/v{version}"
        if args.mode == "release"
        else f"https://raw.githubusercontent.com/soum91/aukkhor/main/downloads/v{version}"
    )
    for filename in ("repo.json", "source.json"):
        path = Path(filename)
        feed = json.loads(path.read_text(encoding="utf-8"))
        apps = feed["apps"]
        main_app = next((a for a in apps if a.get("name") == "Aukkhor"
                         and a.get("bundleIdentifier") == HOST_ID), None)
        if main_app is None:
            raise SystemExit(f"Aukkhor main entry missing in {filename}")
        note = (
            "Aukkhor English and Bangla keyboard with Windows and TV companions. "
            "Contains the main app and one keyboard extension; no Share extension. "
            "Unsigned IPA: signer must preserve and provision both bundle IDs."
        )
        current = list(main_app.get("versions", []))
        main_app["subtitle"] = "iPhone keyboard · " + version
        main_app["localizedDescription"] = note
        main_app["versions"] = [{
            "version": marketing_version,
            "buildVersion": str(args.build),
            "date": datetime.now(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z"),
            "localizedDescription": note,
            "changelog": "Native-style QWERTY rows and wide Space; side tools follow one-handed layout; native Liquid Glass, removable backgrounds on every key, custom colors/opacity/spacing/height and real keyboard preview. Retains native text replacements, number row, emoji, OTP Shortcuts, Windows clipboard and direct TV typing. Host plus keyboard only.",
            "downloadURL": f"{prefix}/{IPA}",
            "size": (args.directory / IPA).stat().st_size,
            "minOSVersion": "16.0",
        }] + [old for old in current if str(old.get("buildVersion")) != str(args.build)][:5]
        # Older Zeus/FlareStore consumers read these top-level fields instead
        # of versions[0]. Leaving them pinned to a previous build silently
        # installed the old keyboard, making already-fixed bugs appear to return.
        synchronize_latest_version(main_app, note)
        apps[:] = [main_app] + [
            a for a in apps
            if a is not main_app
            and a.get("bundleIdentifier") not in {HOST_ID, "dev.soum91.aukkhor.probe"}
            and not a.get("name", "").startswith("Aukkhor ")
            and not a.get("diagnostic", False)
        ]
        path.write_text(json.dumps(feed, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    # Keep the alternate source URL (previously shared with users) updated too.
    # It must never remain pinned to v17 after a successful build.
    alternate = Path("aukkhor-keyboard-v17.json")
    alternate_feed = json.loads(Path("repo.json").read_text(encoding="utf-8"))
    alternate_feed["name"] = "Aukkhor Keyboard"
    alternate_feed["identifier"] = "dev.soum91.aukkhor.source.keyboard.v17"
    alternate_feed["sourceURL"] = "https://raw.githubusercontent.com/soum91/aukkhor/main/aukkhor-keyboard-v17.json"
    alternate_feed["subtitle"] = "Aukkhor keyboard releases"
    alternate_feed["description"] = "Aukkhor iPhone keyboard, host and keyboard extension only. Continuously updated feed."
    alternate.write_text(json.dumps(alternate_feed, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"Published one Aukkhor {version} entry; no probe or diagnostic listings")

if __name__ == "__main__":
    main()
