# Pangolin Newt for OpenWrt

Native OpenWrt packaging and a LuCI management interface for
[Fossorial Newt](https://github.com/fosrl/newt). Newt runs directly under
`procd`; Docker is not required. Pangolin remains the control plane for sites,
resources, targets, and access policy.

The current release targets the FriendlyElec NanoPi R5C:

| Component | Version |
| --- | --- |
| OpenWrt | 25.12.5 |
| Target / package architecture | `rockchip/armv8` / `aarch64_generic` |
| Newt | 1.18.1 |
| Package format | OpenWrt APK v3 |

`luci-app-newt` depends on the architecture-specific `newt` package, so a
normal feed install needs only one package name. The app provides credential or
provisioning-key setup, boot control, `procd` supervision, connected status,
sanitized logs, advanced Newt options, and package-managed updates.

## Install

For the recommended signed-feed installation, direct LuCI upload, and package
verification steps, see **[Installation](docs/INSTALLING.md)**.

For a custom NanoPi R5C image or a paste-ready Firmware Selector first-boot
script, see **[Firmware Selector and ImageBuilder](docs/IMAGEBUILDER.md)**.

After installation, open **Services → Pangolin Newt** in LuCI. The Pangolin
endpoint is a complete HTTPS URL, for example
`https://pangolin.example.com` or `https://pangolin.example.com:8443`.

## Build and verify

```sh
./scripts/build-in-docker.sh
./scripts/verify-artifacts-in-docker.sh
./scripts/build-r5c-image-in-docker.sh
```

The Docker workflow uses the pinned OpenWrt 25.12.5 SDK and ImageBuilder,
verifies source and toolchain checksums, signs the APK feed when the local key
is available, executes the ARM64 binary under QEMU, validates package metadata
and file modes, compiles the ucode RPC backend, and builds both R5C sysupgrade
images. See **[Building and publishing](docs/BUILDING.md)**.

## Documentation

- [Installation](docs/INSTALLING.md)
- [Firmware Selector, first boot, and ImageBuilder](docs/IMAGEBUILDER.md)
- [Architecture and security boundaries](docs/ARCHITECTURE.md)
- [Configuration reference](docs/CONFIGURATION.md)
- [Building and publishing](docs/BUILDING.md)
- [Maintainer handoff](docs/MAINTAINER-HANDOFF.md)

The repository documentation is the canonical source rather than a separate
GitHub Wiki. Keeping it beside the code makes every release's instructions
versioned, reviewable, and available offline.

## Status

Automated package, feed, ARM64 execution, and firmware-image checks pass.
Installation, reboot reconnection, and real tunnel traffic on a physical R5C
remain the final hardware acceptance gate.

The integration code is Apache-2.0. Newt is fetched from its pinned upstream
tag and built under Fossorial's AGPL-3.0/commercial licensing terms; this build
uses the AGPL-3.0 option.
