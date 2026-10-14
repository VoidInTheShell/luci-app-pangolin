# Building and publishing

## Reproducible target

The default build is pinned to OpenWrt 25.12.5 for `rockchip/armv8`, whose
package architecture is `aarch64_generic`. The official SDK checksum is pinned
in `scripts/build-openwrt.sh`. Newt is pinned to tag `1.18.1`, and its source
archive SHA-256 is pinned in `packages/newt/Makefile`.

## Docker build

Docker is the recommended entry point on macOS and Linux:

```sh
./scripts/build-in-docker.sh
```

The SDK and download caches persist in the Docker volume
`openwrt-newt-sdk-cache`; final files are copied to
`dist/openwrt-25.12.5/aarch64_generic/`.

The Docker path supplies the same pinned Go 1.26.9 host compiler selected by
the OpenWrt 25.12 package feed, avoiding the need to run
OpenWrt's legacy bootstrap binaries through cross-architecture Docker
emulation on Apple Silicon. Compilation, ARM64 target flags, packaging, and
index generation still use the official OpenWrt SDK helpers. Native OpenWrt
buildroots use the normal `golang1.26/host` dependency by default.

For a quick source-compilation check without the OpenWrt SDK, build the pinned
static ARM64 binary with:

```sh
./scripts/build-newt-arm64.sh
```

This verifies the upstream source hash and writes
`dist/raw/newt_linux_arm64`. The APK build remains the deployable artifact.

After the APK build succeeds, create generic NanoPi R5C ext4 and squashfs
sysupgrade images with LuCI and Newt preinstalled:

```sh
./scripts/build-r5c-image-in-docker.sh
```

The firmware images contain no Pangolin credentials and are written beneath
`dist/openwrt-25.12.5/aarch64_generic/images/`. See
[ImageBuilder and first boot](IMAGEBUILDER.md) for optional per-device setup.

## Native Linux build

Install `bash`, `curl`, `git`, `make`, `rsync`, `tar`, `zstd`, standard GNU
build utilities, and the normal OpenWrt SDK prerequisites. Then run:

```sh
./scripts/build-openwrt.sh
```

Override the defaults when deliberately changing release lines:

```sh
OPENWRT_VERSION=25.12.5 \
OPENWRT_TARGET=rockchip \
OPENWRT_SUBTARGET=armv8 \
./scripts/build-openwrt.sh
```

To reuse an extracted SDK:

```sh
OPENWRT_SDK_DIR=/opt/openwrt-sdk ./scripts/build-openwrt.sh
```

## Package checks

Run the repository-level checks without an SDK:

```sh
./tests/check.sh
```

The SDK build is the authoritative packaging test. It also verifies that both
APK files exist and that the Newt artifact is assigned `aarch64_generic` while
the LuCI artifact is `noarch`.

The repository additionally runs the ARM64 executable under an ARM64 Linux
container (through binfmt/QEMU when the build host is x86-64) and inspects the
APK payload, modes, architecture, dependency list, LuCI RPC files, and feed
database before a release is published.

## Local installation

Copy the two APKs to `/tmp` on a matching OpenWrt 25.12 R5C and install them:

```sh
apk add --allow-untrusted /tmp/newt-1.18.1-r1.apk \
  /tmp/luci-app-newt-1.0.0-r1.apk
```

`--allow-untrusted` is appropriate only for a one-off development build whose
hash you verified out of band. Public distribution should use a signed feed.

## Public APK feed

OpenWrt APK repositories use a P-256 EC key. Keep the private key outside Git;
publish only `public-key.pem`. The release builder places the private key at the
SDK root as `private-key.pem`, enables signed packages, runs `make package/index`,
and publishes the generated `packages.adb` beside the APK files.

On the router:

```sh
install -m 0644 /tmp/openwrt-newt-public-key.pem \
  /etc/apk/keys/openwrt-newt-public-key.pem
echo 'https://github.com/alexanderjlynn/openwrt-newt/releases/latest/download/packages.adb' \
  > /etc/apk/repositories.d/openwrt-newt.list
apk update
apk add luci-app-newt
```

The public key and feed URL remain stable across releases.

## Hardware verification checklist

1. Confirm `ubus call system board`, `apk --print-arch`, and `uname -a`.
2. Install both APKs and verify `/etc/config/newt` is mode `0600`.
3. Configure endpoint, ID, and secret in LuCI.
4. Verify `procd` restarts Newt after a forced process exit.
5. Verify the status changes from starting to connected.
6. Verify `logread -e newt` and the LuCI log view agree.
7. Verify the secret is absent from `ps`, ubus service output, RPC responses,
   and LuCI browser network responses.
8. Reboot and verify automatic startup and reconnection.
9. Exercise provisioning-key conversion on a disposable Pangolin site.
10. Install an upgraded APK and verify UCI settings are retained.
