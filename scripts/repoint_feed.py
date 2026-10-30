#!/usr/bin/env python3
"""Select verified Aukkhor IPA download locations for the FlareStore catalogs.

Only run after download artifacts were produced by a successful iOS CI run.
A direct-file fallback is used only when GitHub refuses to create a Release.
"""
import argparse
import json
import zipfile
from pathlib import Path

BASE = "https://raw.githubusercontent.com/soum91/aukkhor/main"
RELEASE_BASE = "https://github.com/soum91/aukkhor/releases/download"


def validate_ipa(path: Path) -> None:
    if not path.is_file() or path.stat().st_size < 100_000:
        raise SystemExit("IPA missing or unexpectedly small: " + str(path))
    with zipfile.ZipFile(path) as archive:
        contents = set(archive.namelist())
        required = (
            "Payload/Aukkhor.app/Info.plist",
            "Payload/Aukkhor.app/PlugIns/AukkhorKeyboard.appex/Info.plist",
            "Payload/Aukkhor.app/PlugIns/AukkhorShare.appex/Info.plist",
        )
        missing = [name for name in required if name not in contents]
        if missing:
            raise SystemExit("Incomplete iOS package: " + ", ".join(missing))


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--build", required=True, type=int)
    parser.add_argument("--mode", required=True, choices=("release", "direct"))
    parser.add_argument("--ipa", required=True, type=Path)
    parser.add_argument("--compat", required=True, type=Path)
    args = parser.parse_args()
    validate_ipa(args.ipa)
    validate_ipa(args.compat)
    version = f"0.2.0.{args.build}"
    if args.mode == "direct":
        prefix = f"{BASE}/downloads/v{version}"
    else:
        prefix = f"{RELEASE_BASE}/v{version}"
    notes = (
        "iPhone keyboard with English, phonetic Bangla and direct Bangla, themes, "
        "TV focused-field typing, and opt-in Windows remote typing. "
        "Compatibility IPA is available with reduced cross-extension entitlements. "
        "Unsigned previews: sign all app extensions and the host app correctly."
    )
    for name in ("repo.json", "source.json"):
        path = Path(name)
        data = json.loads(path.read_text(encoding="utf-8"))
        apps = data.get("apps", [])
        if len(apps) != 1 or apps[0].get("bundleIdentifier") != "dev.soum91.aukkhor":
            raise SystemExit("Unexpected feed structure in " + name)
        items = apps[0].get("versions", [])
        entry = next((x for x in items if x.get("version") == version), None)
        if entry is None:
            raise SystemExit("Run scripts/update_feed.py first: missing " + version)
        entry["downloadURL"] = f"{prefix}/Aukkhor-unsigned.ipa"
        entry["compatibilityURL"] = f"{prefix}/Aukkhor-compat-unsigned.ipa"
        entry["localizedDescription"] = notes
        entry["changelog"] = notes
        entry["size"] = args.ipa.stat().st_size
        apps[0]["versions"] = [entry] + [
            previous for previous in items if previous.get("version") != version
        ]
        path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print("Aukkhor FlareStore " + version + " distribution mode: " + args.mode)


if __name__ == "__main__":
    main()
