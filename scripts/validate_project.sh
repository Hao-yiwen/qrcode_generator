#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

python3 <<'PY'
from pathlib import Path
import re
import sys
import xml.etree.ElementTree as ET

errors: list[str] = []
warnings: list[str] = []

pbx = Path("qrcode_generator.xcodeproj/project.pbxproj").read_text()
if pbx.count("{") != pbx.count("}"):
    errors.append("pbxproj brace mismatch")

deploy = set(re.findall(r"MACOSX_DEPLOYMENT_TARGET = ([^;]+);", pbx))
swift = set(re.findall(r"SWIFT_VERSION = ([^;]+);", pbx))
strict = set(re.findall(r"SWIFT_STRICT_CONCURRENCY = ([^;]+);", pbx))
if deploy != {"13.5"}:
    errors.append(f"unexpected MACOSX_DEPLOYMENT_TARGET: {deploy}")
if swift != {"5.0"}:
    errors.append(f"unexpected SWIFT_VERSION: {swift}")
if strict != {"targeted"}:
    errors.append(f"expected SWIFT_STRICT_CONCURRENCY=targeted, got {strict}")

src = Path("qrcode_generator/qrcode_generatorApp.swift").read_text()
required = {
    "@NSApplicationDelegateAdaptor(AppDelegate.self)": True,
    "MenuBarExtraCoordinator": True,
    "viewDidMoveToWindow": True,
    "responds(to: selector)": True,
    "NSApp.activate()": True,
    "filter.message = Data(string.utf8)": True,
    "menuBarExtraStyle(.window)": True,
    "@MainActor\nfinal class AppStateManager": True,
    "RemoveEventHandler": True,
}
for token, _ in required.items():
    if token not in src:
        errors.append(f"missing required token: {token}")

forbidden = [
    "import UserNotifications",
    "foregroundColor(",
    'setValue(data, forKey: "inputMessage")',
    "PlainTextFieldStyle()",
    "PlainButtonStyle()",
    "setupStatusItem()",
    "setupPopover()",
    "SWIFT_VERSION = 5.10",
    "showsIndicators:",
    ".cornerRadius(",
]
for token in forbidden:
    if token in src or token in pbx:
        errors.append(f"forbidden pattern still present: {token}")

if "struct QRCodeGeneratorView" in src:
    warnings.append("unused QRCodeGeneratorView removed? still present")

for plist in [
    "qrcode-generator-Info.plist",
    "qrcode_generator/qrcode_generator.entitlements",
]:
    ET.parse(plist)

scheme = Path("qrcode_generator.xcodeproj/xcshareddata/xcschemes/qrcode_generator.xcscheme").read_text()
if "LastUpgradeVersion = \"1600\"" not in scheme:
    warnings.append("scheme LastUpgradeVersion is not 1600")

print("DEPLOYMENT:", sorted(deploy))
print("SWIFT:", sorted(swift))
print("CONCURRENCY:", sorted(strict))
print("filter.message count:", src.count("filter.message = Data(string.utf8)"))
print("foregroundStyle count:", src.count(".foregroundStyle("))

if warnings:
    print("\nWARNINGS:")
    for w in warnings:
        print(" -", w)

if errors:
    print("\nFAILED:")
    for e in errors:
        print(" -", e)
    sys.exit(1)

print("\nVALIDATION PASSED")
PY