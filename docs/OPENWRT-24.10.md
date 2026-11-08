# OpenWrt 24.10 IPK bundles

The client build supports OpenWrt 24.10.2 for `x86_64`,
`aarch64_generic` (ARM64), and `aarch64_cortex-a53` (MediaTek Filogic),
alongside the existing 25.12.5 APK builds.
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
# Or MediaTek Filogic / Cortex-A53:
# export OPENWRT_TARGET=mediatek OPENWRT_SUBTARGET=filogic OPENWRT_PACKAGE_ARCH=aarch64_cortex-a53
bash scripts/build-openwrt.sh
```

Outputs are written to `dist/openwrt-24.10.2/<architecture>/`. SDK archives
are checked against pinned official SHA256 values before extraction.
Set `OPENWRT_APK_PRIVATE_KEY_FILE` and `OPENWRT_PUBLIC_KEY_FILE` to sign the
checksum list. The legacy environment variable name is shared with APK builds;
the private key is never included in the output.

## Verify and install

Choose the bundle matching `opkg print-architecture`. Both `tar.gz` and ZIP
contain the same complete installation files. Standalone IPKs are also available
with firmware and architecture in their filenames; use both the client and LuCI
IPKs from the same platform. Their matching `*-ipk-SHA256SUMS` and `.sig` are
covered in [release installation](RELEASING.md#安装资产与签名).

Match the package architecture exactly: a router listing only
`aarch64_cortex-a53` will reject the `aarch64_generic` CLI IPK even though
both are ARM64. Use the Cortex-A53 release instead of changing opkg's
architecture configuration or forcing installation.

For a complete bundle, verify the public key against a trusted copy before
checking the signature on a computer:

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

Both IPKs declare their runtime dependencies. The release bundle contains the
client core and LuCI interface; it does not bundle every system dependency.
With working firmware feeds, `opkg update` followed by the install command above
resolves and installs missing dependencies automatically. Offline installation
also requires local copies of every missing dependency.

| Package | Runtime dependencies declared by the IPK |
| --- | --- |
| `pangolin-cli` | `libc`, `ca-bundle`, `curl`, `jshn`, `kmod-tun`, `ucode`, `ucode-mod-fs`, `ucode-mod-uci` |
| `luci-app-pangolin` | `libc`, `luci-base`, `rpcd-mod-ucode`, `ucode-mod-fs`, `ucode-mod-uci`, `ucode-mod-ubus` |

Install both packages for a complete client. `luci-app-pangolin` intentionally
does not depend on `pangolin-cli`, so installing only the LuCI IPK does not
automatically install the client core. The core includes `/usr/bin/pangolin`
with its Newt and OLM Go modules compiled in. Client and Subnet Router use do
not require the separate `newt` or `luci-app-newt` packages.

Open **VPN → Pangolin**, save the server address, then authenticate the device.
Successful authentication automatically enables and starts the service, including
reauthentication and authentication after logout. Installation itself leaves the
VPN disabled by default; boot autostart is a separate setting.
