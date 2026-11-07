# OpenWrt 24.10 IPK bundles

The client build supports OpenWrt 24.10.2 for `x86_64` and
`aarch64_generic` (ARM64), alongside the existing 25.12.5 APK builds.
The CLI and LuCI package use the same sources and features on both releases.
Firmware images remain specific to their original board targets.

## Build

Run on Linux with Go 1.26 or newer and the SDK prerequisites:

```sh
export PANGOLIN_CLIENT_ONLY=1 PANGOLIN_USE_EXTERNAL_GO=1
export OPENWRT_VERSION=24.10.2
# x86_64:
export OPENWRT_TARGET=x86 OPENWRT_SUBTARGET=64 OPENWRT_PACKAGE_ARCH=x86_64
# Or ARM64:
# export OPENWRT_TARGET=rockchip OPENWRT_SUBTARGET=armv8 OPENWRT_PACKAGE_ARCH=aarch64_generic
bash scripts/build-openwrt.sh
```

Outputs are written to `dist/openwrt-24.10.2/<architecture>/`. SDK archives
are checked against pinned official SHA256 values before extraction.
Set `OPENWRT_APK_PRIVATE_KEY_FILE` and `OPENWRT_PUBLIC_KEY_FILE` to sign the
checksum list. The legacy environment variable name is shared with APK builds;
the private key is never included in the output.

## Verify and install

Choose the bundle matching `opkg print-architecture`. Verify the public key
against a trusted copy before checking the signature on a computer:

```sh
openssl dgst -sha256 -verify pangolin-public-key.pem \
  -signature packages-sha256sums.sig packages-sha256sums
```

Copy the extracted bundle to `/tmp/pangolin-release` on the router:

```sh
cd /tmp/pangolin-release
sha256sum -c packages-sha256sums
opkg update
opkg install ./pangolin-cli_*.ipk ./luci-app-pangolin_*.ipk
/etc/init.d/rpcd restart
```

The bundle authenticates local IPKs with an OpenSSL-signed checksum list.
`Packages` and `Packages.gz` are informational indexes, not a usign-signed
feed. Do not add them as a trusted opkg feed or use an APK key as a usign key.
Keep the router's own firmware feeds enabled for runtime dependencies,
especially the kernel-matched `kmod-tun`. The client IPKs do not contain
kernel modules, device credentials or saved user configuration.

Open **VPN → Pangolin**, authenticate the device, enable the service, then
save and apply. Installation leaves the VPN disabled by default.
