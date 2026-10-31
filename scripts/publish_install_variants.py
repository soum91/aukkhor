#!/usr/bin/env python3
"""Publish all four audited Aukkhor iOS signing-test variants in FlareStore JSON.

Never falsify a bundle ID. Three variants of Aukkhor intentionally share the
same app ID, so they replace each other; standalone probe has a distinct ID.
The APK/IPA data is not self-signed here. The four files must originate from
the SAME successful iOS CI run and must be available at the referenced URLs.
"""
import argparse
import json
import plistlib
import zipfile
from datetime import date
from pathlib import Path

EXPECTED = {
    "Aukkhor-unsigned.ipa": ("dev.soum91.aukkhor", {"AukkhorKeyboard.appex", "AukkhorShare.appex"}),
    "Aukkhor-compat-unsigned.ipa": ("dev.soum91.aukkhor", {"AukkhorKeyboard.appex", "AukkhorShare.appex"}),
    "Aukkhor-keyboard-only-unsigned.ipa": ("dev.soum91.aukkhor", {"AukkhorKeyboard.appex"}),
    "Aukkhor-standalone-probe-unsigned.ipa": ("dev.soum91.aukkhor.probe", set()),
}
VARIANTS = [
    (
        "Aukkhor Compatibility Test",
        "Aukkhor-compat-unsigned.ipa",
        "No App Group or shared Keychain entitlements. Main app and two extensions, but cross-extension settings and pairing may not work.",
    ),
    (
        "Aukkhor Keyboard-Only Test",
        "Aukkhor-keyboard-only-unsigned.ipa",
        "Main app plus keyboard extension only. No Share extension and no optional sharing entitlements.",
    ),
    (
        "Aukkhor Standalone Install Probe",
        "Aukkhor-standalone-probe-unsigned.ipa",
        "Installation diagnostic: containing app only, no keyboard or Share extension. Not a functioning keyboard.",
    ),
]


def inspect(path: Path):
    if not path.is_file() or path.stat().st_size < 100_000:
        raise SystemExit(f"Missing/small IPA: {path}")
    with zipfile.ZipFile(path) as archive:
        names = set(archive.namelist())
        app_plist = "Payload/Aukkhor.app/Info.plist"
        if app_plist not in names:
            raise SystemExit(f"Invalid IPA: no app plist in {path}")
        root = plistlib.loads(archive.read(app_plist))
        bundle = root.get("CFBundleIdentifier")
        extensions = set()
        for name in names:
            if name.startswith("Payload/Aukkhor.app/PlugIns/") and name.endswith(".appex/Info.plist"):
                extensions.add(name.split("/")[3])
        expected_id, expected_extensions = EXPECTED[path.name]
        if bundle != expected_id or extensions != expected_extensions:
            raise SystemExit(f"Package mismatch in {path.name}: bundle={bundle} extensions={extensions}")
        print(f"Verified {path.name}: {bundle}, extensions {sorted(extensions)}")
        return bundle


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--build", required=True, type=int)
    parser.add_argument("--directory", required=True, type=Path)
    parser.add_argument("--mode", required=True, choices=("release", "direct"))
    args = parser.parse_args()
    version = f"0.2.0.{args.build}"
    prefix = (
        f"https://github.com/soum91/aukkhor/releases/download/v{version}"
        if args.mode == "release"
        else f"https://raw.githubusercontent.com/soum91/aukkhor/main/downloads/v{version}"
    )
    for filename in EXPECTED:
        inspect(args.directory / filename)
    for file_name in ("repo.json", "source.json"):
        path = Path(file_name)
        feed = json.loads(path.read_text(encoding="utf-8"))
        apps = feed["apps"]
        main_app = next((a for a in apps if a.get("name") == "Aukkhor"
                         and a.get("bundleIdentifier") == "dev.soum91.aukkhor"), None)
        if not main_app:
            raise SystemExit(f"Primary Aukkhor entry missing in {file_name}")
        icon = main_app["iconURL"]
        new_entries = []
        for name, ipa_name, explanation in VARIANTS:
            ident = EXPECTED[ipa_name][0]
            note = (
                explanation + " Unsigned IPA, must sign with valid iOS certificate and compatible "
                "provisioning. This diagnostic may replace another Aukkhor variant with "
                "the same bundle ID."
            )
            new_entries.append({
                "name": name,
                "bundleIdentifier": ident,
                "developerName": "soum91",
                "subtitle": "Aukkhor installation diagnostic · " + version,
                "localizedDescription": note,
                "category": "utilities",
                "iconURL": icon,
                "diagnostic": True,
                "versions": [{
                    "version": version,
                    "buildVersion": str(args.build),
                    "date": date.today().isoformat(),
                    "localizedDescription": note,
                    "changelog": note,
                    "downloadURL": f"{prefix}/{ipa_name}",
                    "size": (args.directory / ipa_name).stat().st_size,
                    "minOSVersion": "16.0",
                }],
            })
        apps[:] = ([main_app] + new_entries + [
            app for app in apps
            if app is not main_app and not app.get("diagnostic", False)
        ])
        path.write_text(json.dumps(feed, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"Aukkhor {version}: four entries available, mode={args.mode}")


if __name__ == "__main__":
    main()
