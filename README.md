# LuCI app for Pangolin Newt

This repository packages [Fossorial Newt](https://github.com/fosrl/newt) for
OpenWrt and adds a full LuCI management interface. The initial supported target
is OpenWrt 25.12 on the FriendlyElec NanoPi R5C.

## Target

| Component | Value |
| --- | --- |
| Board | FriendlyElec NanoPi R5C |
| SoC | Rockchip RK3568B2 |
| OpenWrt target | `rockchip/armv8` |
| OpenWrt package architecture | `aarch64_generic` |
| Newt | `1.18.1` |
| Package format | APK (OpenWrt 25.12+) |

Two packages are produced:

- `newt-1.18.1-r1.apk` contains the ARM64 binary, UCI configuration, and
  `procd` service.
- `luci-app-newt-1.0.0-r1.apk` is architecture-independent and depends on
  `newt`. Installing the LuCI package from a feed installs both automatically.

The architecture belongs on the binary package metadata, not in the LuCI app's
name. This lets the same `luci-app-newt` package work if more Newt architectures
are published later.

## Features

- Direct `procd` supervision with crash restart and boot enablement.
- Existing ID/secret and one-time provisioning-key setup flows.
- Pangolin endpoint, networking, timing, mTLS, SSH/auth-daemon, metrics,
  diagnostics, and process controls.
- Live service, PID, version, uptime, and tunnel-health status.
- Start, stop, restart, enable-at-boot, and disable-at-boot actions.
- Live, copyable, server-side-sanitized system logs.
- Package patch removes upstream debug messages that would expose temporary
  authentication tokens or provisioning response bodies to `logd`.
- Root-only persistent and runtime configuration files.
- Secrets are never returned to browser-side LuCI code.
- Newt's in-place self-updater is suppressed; upgrades remain owned by `apk`.

Pangolin remains the control plane for sites, resources, targets, access rules,
and tunnel behavior. LuCI manages only the local connector.

## Build

The reproducible Linux build uses the official OpenWrt 25.12.5
`rockchip/armv8` SDK:

```sh
./scripts/build-in-docker.sh
```

To compile only the static ARM64 Newt binary first:

```sh
./scripts/build-newt-arm64.sh
```

Artifacts are copied to `dist/openwrt-25.12.5/aarch64_generic/`. To use an
already extracted SDK on Linux:

```sh
OPENWRT_SDK_DIR=/path/to/openwrt-sdk ./scripts/build-openwrt.sh
```

See [Building](docs/BUILDING.md), [Architecture](docs/ARCHITECTURE.md), and
[Configuration reference](docs/CONFIGURATION.md) for the complete design and
option mapping. [ImageBuilder and first boot](docs/IMAGEBUILDER.md) covers
generic firmware images, endpoint presets, and one-time provisioning keys.

## Install from the signed public feed

On an R5C running OpenWrt 25.12, connect with SSH and install this repository's
public signing key and feed URL:

```sh
wget -O /etc/apk/keys/openwrt-newt-public-key.pem \
  https://github.com/alexanderjlynn/openwrt-newt/releases/latest/download/openwrt-newt-public-key.pem
echo 'https://github.com/alexanderjlynn/openwrt-newt/releases/latest/download/packages.adb' \
  > /etc/apk/repositories.d/openwrt-newt.list
apk update
apk add luci-app-newt
```

Refresh LuCI and open **Services → Pangolin Newt**. The `luci-app-newt`
dependency installs the matching ARM64 `newt` package automatically. Future
updates can be installed from **System → Software** or with `apk upgrade`.

The release page also contains a generic R5C sysupgrade image with LuCI and
Newt preinstalled. It contains no Pangolin credentials. Verify its checksum,
take an OpenWrt backup, and use the image only on a NanoPi R5C already running
the matching OpenWrt 25.12 series.

## Install a downloaded release or local build

Copy both APK files to the router, then run:

```sh
apk add --allow-untrusted /tmp/newt-1.18.1-r1.apk \
  /tmp/luci-app-newt-1.0.0-r1.apk
```

Refresh LuCI and open **Services → Pangolin Newt**. Paste the endpoint, Newt
ID, and secret from the Pangolin site setup page, enable the service, and save.

You can also install the two files from LuCI: open **System → Software**, use
**Upload Package** for `newt` first and `luci-app-newt` second, then refresh the
browser. The signed public feed eliminates this two-file/manual dependency
ordering; after adding that feed, search for and install only
`luci-app-newt` under **Available packages**.

Do not use `opkg` or `.ipk` packages on OpenWrt 25.12. OpenWrt 25.12 and newer
use `apk` and `.apk` packages.

## Preinstalled image and first boot

Build generic NanoPi R5C ext4 and squashfs sysupgrade images after the package
build with:

```sh
./scripts/build-r5c-image-in-docker.sh
```

These images contain LuCI and Newt but no Pangolin credential. For a safe
endpoint-only preset, a private per-device provisioning-key image, or post-boot
SSH provisioning, follow [ImageBuilder and first boot](docs/IMAGEBUILDER.md).
Newt 1.18.1 does not expose an approval-only enrollment option; its supported
unattended flow is a one-time Pangolin provisioning key plus a unique site name.
That guide also includes a paste-ready OpenWrt Firmware Selector first-boot
script which installs from this signed feed.

## Verification status

CI and the Docker workflow perform the pinned source build, OpenWrt SDK package
build, LuCI compilation, package-index generation, ARM64 execution check, APK
content/metadata checks, and NanoPi R5C ImageBuilder build. Installation,
reconnection, and tunnel traffic on a physical R5C remain the final hardware
acceptance gate.

## Licensing

The original OpenWrt/LuCI integration in this repository is Apache-2.0. Newt is
fetched from upstream at build time and is licensed by Fossorial under
AGPL-3.0 and its commercial license; this build and its source patch use the
AGPL-3.0 option. The corresponding Newt source tag, exact archive hash, and
applied patch are all present in this repository.
