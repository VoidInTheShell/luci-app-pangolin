# Building and publishing

## Reproducible pins

| Input | Pin |
| --- | --- |
| OpenWrt SDK / ImageBuilder | 25.12.5, `rockchip/armv8` |
| Package architecture | `aarch64_generic` |
| Pangolin CLI | 0.18.1 |
| Newt | 1.18.1 |
| OLM | 1.10.1 |
| Go toolchain | 1.26.9 |

All Fossorial source archives and official OpenWrt archives have SHA-256 pins.
The CLI recipe replaces its Newt and OLM Go modules with those exact unpacked
sources before applying narrow security patches.

## Docker or Rancher Desktop

On macOS or Linux:

```sh
./tests/check.sh
./scripts/build-in-docker.sh
./scripts/verify-artifacts-in-docker.sh
./scripts/build-r5c-image-in-docker.sh
```

The persistent volume `openwrt-newt-sdk-cache` holds SDK/download state.
Artifacts are written to `dist/openwrt-25.12.5/aarch64_generic/`. On Apple
Silicon, x86-64 SDK host tools run under emulation; the first build is slower
than native x86-64 CI.

The Docker image supplies Go 1.26.9. Cross flags, dependency metadata,
packaging, signing, target ucode, and repository generation still come from
the official OpenWrt SDK.

## Native Linux

Install standard OpenWrt SDK prerequisites plus Bash, curl, Git, make, rsync,
tar, zstd, Python, and Go 1.26.9, then run:

```sh
NEWT_USE_EXTERNAL_GO=1 \
PANGOLIN_USE_EXTERNAL_GO=1 \
./scripts/build-openwrt.sh
```

Omit the external-Go variables in a full OpenWrt buildroot. Deliberate target
overrides are available:

```sh
OPENWRT_VERSION=25.12.5 \
OPENWRT_TARGET=rockchip \
OPENWRT_SUBTARGET=armv8 \
OPENWRT_SDK_DIR=/opt/openwrt-sdk \
./scripts/build-openwrt.sh
```

Changing OpenWrt versions also requires updating archive names/hashes, package
expectations, the ImageBuilder pin, and CI cache key.

## Outputs

The signed feed contains:

```text
pangolin-cli-0.18.1-r2.apk
luci-app-pangolin-1.0.0-r3.apk
newt-1.18.1-r3.apk
luci-app-newt-1.0.0-r4.apk
packages.adb
index.json
packages-sha256sums
openwrt-newt-public-key.pem
```

The Newt pair is compatibility-only. New images install
`luci-app-pangolin` and its dependencies.

## Verification coverage

`tests/check.sh` validates shell/JavaScript/Python syntax, JSON descriptors,
source pins, required files, security-patch markers, the `site` procd/RPC
instance contract, network/firewall invariants, and negative bootstrap inputs.

`tests/test_rpc_backends_openwrt.sh` checksum-verifies an official OpenWrt
25.12.5 rootfs and exercises configuration saves, service transitions,
validation, secret omission, status, and logs through real `rpcd`/`ubus`.
This is intentionally separate from bytecode compilation because ucode can
defer some regular-expression failures until the affected function executes.

`verify-artifacts-in-docker.sh` additionally:

- verifies every APK and `packages.adb` signature;
- checks exact metadata, dependencies, payload, and sensitive file modes;
- verifies both binaries are little-endian AArch64 ELF files;
- executes Newt and Pangolin CLI under ARM64 QEMU;
- checks embedded Newt/OLM/OpenWrt-manager versions; and
- compiles both rpcd ucode backends with the target OpenWrt runtime.

The ImageBuilder test confirms the R5C manifest contains the Pangolin CLI and
LuCI app, then hashes every produced image and manifest.

## Signing and publishing

OpenWrt APK repositories use a P-256 EC signing key. The ignored local
`private-key.pem` and CI secret `OPENWRT_APK_PRIVATE_KEY_B64` must never be
committed, printed, or included in release assets. The build derives the public
key, confirms it matches `keys/openwrt-newt-public-key.pem`, copies the private
key into the SDK only while signing, and removes it through a trap.

Release procedure:

1. Recheck current OpenWrt, CLI, Newt, and OLM releases and relevant upstream
   issues.
2. Rebase security patches and run all four commands above.
3. Pass the physical R5C acceptance gate.
4. Commit and push `main`; wait for branch CI.
5. Tag `v<pangolin-version>-openwrt<revision>` only after CI is green.
6. Let the tag workflow publish signed feed and image assets.
7. Download the public release and independently verify signatures/hashes.

Tags containing `-rc` are published as GitHub prereleases. GitHub excludes
prereleases from `/releases/latest`, so the signed stable feed remains on the
known-good release while native-main or other higher-risk changes are tested.

## Physical R5C acceptance gate

1. Verify board/release/architecture and `/dev/net/tun`.
2. Install from the signed feed through LuCI.
3. Enter a real Site ID/secret, pass HTTP and TCP reverse-proxy traffic, and
   reboot.
4. Kill the process and confirm `procd` respawns it and LuCI reports the new
   PID/status.
5. Confirm errors and logs appear in LuCI and `logread -e pangolin`.
6. Confirm secrets are absent from argv, ubus output, RPC/browser responses,
   and logd.
7. Exercise provisioning and verify UCI/runtime files remain `0600` and the
   one-time key is cleared.
8. Verify upgrade retains `/etc/config/pangolin`.
9. If deliberately testing native-main, validate the TUN, routes/counters,
   LuCI interface, and firewall zone while accounting for upstream issue #403.

Real control-plane connectivity and traffic on physical hardware are the only
gates the container pipeline cannot replace.
