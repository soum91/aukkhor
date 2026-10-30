#!/usr/bin/env python3
"""Generate a sideload-friendly XcodeGen spec without optional shared entitlements.

The compatibility target retains the iOS keyboard and Share extension. Without an
App Group/keychain-sharing entitlement, extension preferences and paired Windows
credentials are isolated by the OS. No capability is silently promised.
"""
from pathlib import Path
import re

root = Path(__file__).resolve().parents[1] / "ios"
original = (root / "project.yml").read_text(encoding="utf-8")
result, count = re.subn(r"(?m)^    entitlements:\n      path: [^\n]+\n", "", original)
if count != 3:
    raise SystemExit(f"Expected exactly 3 entitlements sections; found {count}")
(root / "project-compat.yml").write_text(result, encoding="utf-8")
print("Generated compatibility Xcode project definition: no App Group or Keychain access groups")
