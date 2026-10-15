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
pangolin_meta = json.loads((root / "pangolin.json").read_text())
luci_pangolin_meta = json.loads((root / "luci-pangolin.json").read_text())
feed_meta = json.loads((root / "feed.json").read_text())

newt_info = newt_meta["info"]
luci_info = luci_meta["info"]
pangolin_info = pangolin_meta["info"]
luci_pangolin_info = luci_pangolin_meta["info"]

assert newt_info["name"] == "newt"
assert newt_info["version"] == "1.18.1-r3"
assert newt_info["arch"] == "aarch64_generic"
assert newt_info["license"] == "AGPL-3.0-only"
assert {"ca-bundle", "ucode", "ucode-mod-fs", "ucode-mod-uci"} <= set(newt_info["depends"])

assert luci_info["name"] == "luci-app-newt"
assert luci_info["version"] == "1.0.0-r4"
assert luci_info["arch"] == "noarch"
assert {"luci-base", "newt", "rpcd-mod-ucode"} <= set(luci_info["depends"])

assert pangolin_info["name"] == "pangolin-cli"
assert pangolin_info["version"] == "0.18.1-r2"
assert pangolin_info["arch"] == "aarch64_generic"
assert pangolin_info["license"] == "AGPL-3.0-only"
assert {"ca-bundle", "kmod-tun", "ucode", "ucode-mod-fs", "ucode-mod-uci"} <= set(pangolin_info["depends"])

assert luci_pangolin_info["name"] == "luci-app-pangolin"
assert luci_pangolin_info["version"] == "1.0.0-r3"
assert luci_pangolin_info["arch"] == "noarch"
assert {"luci-base", "pangolin-cli", "rpcd-mod-ucode"} <= set(luci_pangolin_info["depends"])

assert feed_meta == {
    "version": 2,
    "architecture": "aarch64_generic",
    "packages": {
        "luci-app-newt": "1.0.0-r4",
        "luci-app-pangolin": "1.0.0-r3",
        "newt": "1.18.1-r3",
        "pangolin-cli": "0.18.1-r2",
    },
}

binary = root / "newt-root/usr/bin/newt"
blob = binary.read_bytes()
assert blob[:4] == b"\x7fELF"
assert blob[4] == 2  # ELFCLASS64
assert blob[5] == 1  # little-endian
assert struct.unpack_from("<H", blob, 18)[0] == 183  # EM_AARCH64
assert b"linux_arm64" in blob
assert b"1.18.1" in blob

pangolin_binary = root / "pangolin-root/usr/bin/pangolin"
pangolin_blob = pangolin_binary.read_bytes()
assert pangolin_blob[:4] == b"\x7fELF"
assert pangolin_blob[4] == 2
assert pangolin_blob[5] == 1
assert struct.unpack_from("<H", pangolin_blob, 18)[0] == 183
assert b"0.18.1" in pangolin_blob
assert b"1.18.1" in pangolin_blob
assert b"openwrt" in pangolin_blob
assert (root / "pangolin-root/usr/share/pangolin/version").read_text().strip() == "0.18.1"
assert (root / "pangolin-root/usr/share/pangolin/newt-version").read_text().strip() == "1.18.1"

expected_modes = {
    root / "newt-root/etc/config/newt": 0o600,
    root / "newt-root/etc/init.d/newt": 0o755,
    root / "newt-root/usr/libexec/configure-newt": 0o755,
    root / "newt-root/usr/libexec/newt-run": 0o755,
    root / "newt-root/usr/libexec/newt-sync-credentials": 0o755,
    root / "newt-root/usr/libexec/newt-service-action": 0o755,
    root / "luci-root/usr/share/rpcd/ucode/luci.newt": 0o755,
    root / "luci-root/usr/share/rpcd/acl.d/luci-app-newt.json": 0o644,
    root / "luci-root/usr/share/luci/menu.d/luci-app-newt.json": 0o644,
    root / "luci-root/www/luci-static/resources/view/newt/overview.js": 0o644,
    root / "pangolin-root/etc/config/pangolin": 0o600,
    root / "pangolin-root/etc/init.d/pangolin": 0o755,
    root / "pangolin-root/usr/bin/pangolin": 0o755,
    root / "pangolin-root/usr/libexec/configure-pangolin": 0o755,
    root / "pangolin-root/usr/libexec/pangolin-network": 0o755,
    root / "pangolin-root/usr/libexec/pangolin-service-action": 0o755,
    root / "pangolin-root/usr/libexec/pangolin-site-run": 0o755,
    root / "pangolin-root/usr/libexec/pangolin-site-sync-credentials": 0o755,
    root / "pangolin-root/usr/share/pangolin/version": 0o644,
    root / "pangolin-root/usr/share/pangolin/newt-version": 0o644,
    root / "luci-pangolin-root/usr/share/rpcd/ucode/luci.pangolin": 0o755,
    root / "luci-pangolin-root/usr/share/rpcd/acl.d/luci-app-pangolin.json": 0o644,
    root / "luci-pangolin-root/usr/share/luci/menu.d/luci-app-pangolin.json": 0o644,
    root / "luci-pangolin-root/www/luci-static/resources/view/pangolin/overview.js": 0o644,
}

for path, expected_mode in expected_modes.items():
    if not path.is_file():
        fail(f"missing APK payload file: {path}")
    actual_mode = os.stat(path).st_mode & 0o777
    if actual_mode != expected_mode:
        fail(f"incorrect mode for {path}: {actual_mode:o}, expected {expected_mode:o}")

print("All APK metadata, feed metadata, payload, permissions, and ARM64 ELF checks passed.")
