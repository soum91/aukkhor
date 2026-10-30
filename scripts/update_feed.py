"""Publish a verified release into FlareStore-compatible feed aliases.

Only run after the referenced IPA has been uploaded to the matching GitHub release.
"""

import argparse
import json
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ICON = "https://raw.githubusercontent.com/soum91/aukkhor/main/ios/Assets.xcassets/AppIcon.appiconset/AukkhorIcon.png"
SOURCE = "https://raw.githubusercontent.com/soum91/aukkhor/main/repo.json"
CHANGES = (
    "Preview build: English, phonetic Bangla and direct Bangla; theme presets and "
    "custom photo themes; clipboard controls, Siri Shortcuts, and Windows code sharing. "
    "Redesigned Aukkhor monogram icon with fused Latin A and Bengali অ. "
    "Unsigned IPA: sign with your own valid iOS provisioning profile."
)


def update(version: str, build_number: str, ipa: Path) -> None:
    if not ipa.is_file() or ipa.stat().st_size == 0:
        raise ValueError("Cannot publish a missing or empty IPA")
    data = json.loads((ROOT / "repo.json").read_text(encoding="utf-8"))
    app = {
        "name": "Aukkhor",
        "bundleIdentifier": "dev.soum91.aukkhor",
        "developerName": "soum91",
        "subtitle": "Keyboard, themes, clipboard and Windows companion",
        "localizedDescription": (
            "English, phonetic Bangla and direct Bangla keyboard with on-device themes, "
            "dictionary and speech tools, plus opt-in paired Windows clipboard/code handoff."
        ),
        "category": "utilities",
        "iconURL": ICON,
        "versions": [],
    }
    if data.get("apps"):
        app["versions"] = data["apps"][0].get("versions", [])
    entry = {
        "version": version,
        "buildVersion": build_number,
        "date": datetime.now(timezone.utc).date().isoformat(),
        "localizedDescription": CHANGES,
        "changelog": CHANGES,
        "downloadURL": (
            f"https://github.com/soum91/aukkhor/releases/download/v{version}/Aukkhor-unsigned.ipa"
        ),
        "size": ipa.stat().st_size,
        "minOSVersion": "16.0",
    }
    app["versions"] = [entry] + [
        previous for previous in app["versions"]
        if previous.get("version") != version
    ]
    data["apps"] = [app]
    data["sourceURL"] = SOURCE
    encoded = json.dumps(data, ensure_ascii=False, indent=2) + "\n"
    for name in ("repo.json", "source.json"):
        (ROOT / name).write_text(encoded, encoding="utf-8")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--version", required=True)
    parser.add_argument("--build-number", required=True)
    parser.add_argument("--ipa", type=Path, required=True)
    args = parser.parse_args()
    update(args.version, args.build_number, args.ipa)
