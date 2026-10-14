#!/usr/bin/env python3
import json
import os
import struct
import sys
from pathlib import Path


def fail(message: str) -> None:
    raise SystemExit(message)


if len(sys.argv) != 2:
    fail("usage: verify_artifacts.py VERIFY_ROOT")

root = Path(sys.argv[1])
newt_meta = json.loads((root / "newt.json").read_text())
luci_meta = json.loads((root / "luci.json").read_text())
feed_meta = json.loads((root / "feed.json").read_text())

newt_info = newt_meta["info"]
luci_info = luci_meta["info"]

assert newt_info["name"] == "newt"
assert newt_info["version"] == "1.18.1-r1"
assert newt_info["arch"] == "aarch64_generic"
assert newt_info["license"] == "AGPL-3.0-only"
assert {"ca-bundle", "ucode", "ucode-mod-fs", "ucode-mod-uci"} <= set(newt_info["depends"])

assert luci_info["name"] == "luci-app-newt"
assert luci_info["version"] == "1.0.0-r1"
assert luci_info["arch"] == "noarch"
assert {"luci-base", "newt", "rpcd-mod-ucode"} <= set(luci_info["depends"])

assert feed_meta == {
    "version": 2,
    "architecture": "aarch64_generic",
    "packages": {"luci-app-newt": "1.0.0-r1", "newt": "1.18.1-r1"},
}

binary = root / "newt-root/usr/bin/newt"
blob = binary.read_bytes()
assert blob[:4] == b"\x7fELF"
assert blob[4] == 2  # ELFCLASS64
assert blob[5] == 1  # little-endian
assert struct.unpack_from("<H", blob, 18)[0] == 183  # EM_AARCH64
assert b"linux_arm64" in blob
assert b"1.18.1" in blob

expected_modes = {
    root / "newt-root/etc/config/newt": 0o600,
    root / "newt-root/etc/init.d/newt": 0o755,
    root / "newt-root/usr/libexec/configure-newt": 0o755,
    root / "newt-root/usr/libexec/newt-run": 0o755,
    root / "newt-root/usr/libexec/newt-sync-credentials": 0o755,
    root / "luci-root/usr/share/rpcd/ucode/luci.newt": 0o755,
    root / "luci-root/usr/share/rpcd/acl.d/luci-app-newt.json": 0o644,
    root / "luci-root/usr/share/luci/menu.d/luci-app-newt.json": 0o644,
    root / "luci-root/www/luci-static/resources/view/newt/overview.js": 0o644,
}

for path, expected_mode in expected_modes.items():
    if not path.is_file():
        fail(f"missing APK payload file: {path}")
    actual_mode = os.stat(path).st_mode & 0o777
    if actual_mode != expected_mode:
        fail(f"incorrect mode for {path}: {actual_mode:o}, expected {expected_mode:o}")

print("APK metadata, feed metadata, payload, permissions, and ARM64 ELF checks passed.")
