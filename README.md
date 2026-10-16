# Pangolin site connector for OpenWrt

Native OpenWrt packaging and LuCI management for the official
[Pangolin CLI](https://github.com/fosrl/cli). The service executes
`pangolin up site` directly under `procd`; Docker and systemd are not required.

The LuCI app manages this router's site credentials, process, status, logs, and
advanced connector settings. Pangolin remains the control plane for resources,
targets, access policy, and clients. The legacy `newt`/`luci-app-newt` packages
remain in the feed only for existing installations.

| Component | Pinned version |
| --- | --- |
| OpenWrt | 25.12.5 |
| R5C target / package architecture | `rockchip/armv8` / `aarch64_generic` |
| Pangolin CLI | 0.18.1 |
| Embedded Newt | 1.18.1 |
| Package format | OpenWrt APK v3 |

The current known-good stable release is
[`v0.18.1-openwrt2`](https://github.com/alexanderjlynn/openwrt-newt/releases/tag/v0.18.1-openwrt2).
Its normal userspace site mode is confirmed working on a NanoPi R5C. Native
main-interface work is published only as a prerelease until it passes the same
on-device validation.

## Install

Add the signed package feed over SSH:

```sh
wget -O /tmp/openwrt-newt-public-key.pem \
  https://github.com/alexanderjlynn/openwrt-newt/releases/latest/download/openwrt-newt-public-key.pem
echo '54a584f2a271bddb263225be0ed7e972fd506529adcc03993a8e50bac32c7546  /tmp/openwrt-newt-public-key.pem' \
  | sha256sum -c -
cp /tmp/openwrt-newt-public-key.pem /etc/apk/keys/openwrt-newt-public-key.pem
chmod 0644 /etc/apk/keys/openwrt-newt-public-key.pem
echo 'https://github.com/alexanderjlynn/openwrt-newt/releases/latest/download/packages.adb' \
  > /etc/apk/repositories.d/openwrt-newt.list
apk update
apk add luci-app-pangolin
```

Then open **Services → Pangolin**, enter the endpoint plus the Site ID and
secret shown by Pangolin, enable the connector, and save. The endpoint is an
HTTPS URL; include `:port` only when Pangolin uses a non-default public port.

The default and recommended connector uses Newt's userspace netstack, so it
does not create an OpenWrt interface. The app exposes upstream `native-main`
as an explicitly experimental option and can register its TUN with netifd and
firewall4. Do not enable it merely for reverse proxying.

See [installation and troubleshooting](docs/INSTALLING.md) for LuCI upload and
verification. See [Firmware Selector and first boot](docs/IMAGEBUILDER.md) for
a paste-ready `uci-defaults` script.

### Install the native-main test candidate

The current test release is
[`v0.18.1-openwrt3-rc1`](https://github.com/alexanderjlynn/openwrt-newt/releases/tag/v0.18.1-openwrt3-rc1).
It is a GitHub prerelease and does not replace the stable feed above. On a
router that already has the repository signing key installed, use the
candidate as a temporary signed repository:

```sh
test -s /etc/apk/keys/openwrt-newt-public-key.pem || {
  echo "OpenWrt Newt signing key is missing"
  exit 1
}

echo 'https://github.com/alexanderjlynn/openwrt-newt/releases/download/v0.18.1-openwrt3-rc1/packages.adb' \
  > /etc/apk/repositories.d/openwrt-newt-rc.list

apk update
apk add --upgrade pangolin-cli luci-app-pangolin

/etc/init.d/rpcd restart
/etc/init.d/pangolin restart
```

Verify the installed revisions:

```sh
apk list -I | grep -E '^(pangolin-cli|luci-app-pangolin)-'
```

Expected:

```text
pangolin-cli-0.18.1-r2
luci-app-pangolin-1.0.0-r3
```

An installed `newt-1.18.1-r3` is the separate
legacy connector package; Pangolin CLI embeds Newt 1.18.1 and does not use
that standalone executable. After confirming **Services → Pangolin** connects
without the legacy service, the unused pair may be removed with
`apk del luci-app-newt newt`.

Keep `openwrt-newt-rc.list` while testing the candidate. Remove that file and
run `apk update` when returning exclusively to the stable feed.

Then select **Services → Pangolin → Network → Main tunnel networking
→ Native Linux TUN (experimental)**, enable **Register native interface
with OpenWrt**, and save. See
[native-main prerelease testing](docs/NATIVE-MAIN-TESTING.md) for validation,
firewall behavior, and rollback instructions.

## Build and verify

```sh
./tests/check.sh
./tests/test_rpc_backends_openwrt.sh
./scripts/build-in-docker.sh
./scripts/verify-artifacts-in-docker.sh
./scripts/build-r5c-image-in-docker.sh
```

The pipeline uses checksum-pinned source archives and the OpenWrt 25.12.5 SDK,
cross-compiles AArch64 APKs, executes both RPC backends inside stock OpenWrt
25.12.5 `rpcd`/`ubus`, runs the ARM64 binaries under QEMU, verifies package
signatures/metadata/modes, and builds NanoPi R5C sysupgrade images.

## Documentation

- [Installation and troubleshooting](docs/INSTALLING.md)
- [Native-main prerelease testing](docs/NATIVE-MAIN-TESTING.md)
- [Firmware Selector, first boot, and ImageBuilder](docs/IMAGEBUILDER.md)
- [Configuration reference](docs/CONFIGURATION.md)
- [Architecture and security model](docs/ARCHITECTURE.md)
- [Building and publishing](docs/BUILDING.md)
- [Maintainer handoff](docs/MAINTAINER-HANDOFF.md)

Repository documentation is canonical so code and instructions remain at the
same reviewed revision. Integration code is Apache-2.0; the built Fossorial
components retain their AGPL-3.0/commercial licensing terms and the packages
declare AGPL-3.0.
