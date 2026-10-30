#!/usr/bin/env python3
"""Create progressively simpler iPhone packages to isolate sideload signing failures.

All specs are derived from the same fully compiled app, not fake placeholder content.
- compat: host + keyboard + share, no optional sharing entitlements
- keyboard-only: host + keyboard, no share, no custom entitlements
- standalone-probe: host only, separate bundle identifier, no extensions or entitlements

The probe is a signing/installation diagnostic, NOT a usable keyboard.
"""
from pathlib import Path
import re

root = Path(__file__).resolve().parents[1] / "ios"
original = (root / "project.yml").read_text(encoding="utf-8")
compat, count = re.subn(r"(?m)^    entitlements:\n      path: [^\n]+\n", "", original)
assert count == 3, f"Expected three entitlements sections, got {count}"
(root / "project-compat.yml").write_text(compat, encoding="utf-8")

keyboard_only = compat.replace(
    "      - target: AukkhorShare\n        embed: true\n", ""
)
assert keyboard_only != compat, "Share dependency not found"
keyboard_only, removed = re.subn(
    r"(?ms)^  AukkhorShare:\n.*?(?=^schemes:)", "", keyboard_only
)
assert removed == 1, f"Expected one Share target, got {removed}"
(root / "project-keyboard-only.yml").write_text(keyboard_only, encoding="utf-8")

probe = keyboard_only.replace(
    "    dependencies:\n      - target: AukkhorKeyboard\n        embed: true\n", ""
)
assert probe != keyboard_only, "Keyboard dependency not found"
probe, removed = re.subn(
    r"(?ms)^  AukkhorKeyboard:\n.*?(?=^schemes:)", "", probe
)
assert removed == 1, f"Expected one keyboard target, got {removed}"
probe = probe.replace(
    "PRODUCT_BUNDLE_IDENTIFIER: dev.soum91.aukkhor\n",
    "PRODUCT_BUNDLE_IDENTIFIER: dev.soum91.aukkhor.probe\n", 1
).replace(
    "INFOPLIST_KEY_CFBundleDisplayName: Aukkhor\n",
    "INFOPLIST_KEY_CFBundleDisplayName: Aukkhor Probe\n", 1
)
assert "dev.soum91.aukkhor.probe" in probe, "Probe ID was not set"
(root / "project-standalone-probe.yml").write_text(probe, encoding="utf-8")

for label, spec in (("compat", compat), ("keyboard-only", keyboard_only), ("standalone-probe", probe)):
    assert "entitlements:" not in spec
    print(f"Prepared {label} iOS spec, {spec.count('type: app-extension')} embedded extension targets")
