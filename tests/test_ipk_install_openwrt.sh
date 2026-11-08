#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
arch="${OPENWRT_PACKAGE_ARCH:?}"
package_dir="${OPENWRT_IPK_PACKAGE_DIR:-$repo_root/dist/openwrt-24.10.2/$arch}"
case "$arch" in
	x86_64)
		target=x86/64; name=x86-64; platform=linux/amd64
		sha=5f3725bbeeb4fdfc1a0453de3b15b3f25ed15b5a56878429ea860fad1bf7e6b2 ;;
	aarch64_generic)
		target=armsr/armv8; name=armsr-armv8; platform=linux/arm64
		sha=9ecf04a85530e5d103f45ffb4c78fded3d51d9f39d7a83033bb67c2e4d2ad00d ;;
	aarch64_cortex-a53)
		target=mediatek/filogic; name=mediatek-filogic; platform=linux/arm64
		sha=35a9a327d2186ca650c42410dd5c3b0ad4c8cff5eb2ca47d23449f217af5fcf6 ;;
	*) echo 'Unsupported IPK test architecture' >&2; exit 1 ;;
esac
cache="$repo_root/.cache"
rootfs="$cache/openwrt-24.10.2-$name-rootfs.tar.gz"
if [ "$arch" = aarch64_cortex-a53 ]; then
	# Filogic publishes a SquashFS image rather than a rootfs tarball.
	# Its pinned stock filesystem has the correct opkg architecture and feeds.
	rootfs="$cache/openwrt-24.10.2-mediatek-filogic-cudy_wr3000-v1-squashfs-sysupgrade.bin"
fi
mkdir -p "$cache"
if [ ! -f "$rootfs" ]; then
	curl -fL --retry 3 -o "$rootfs" "https://downloads.openwrt.org/releases/24.10.2/targets/$target/$(basename "$rootfs")"
fi
echo "$sha  $rootfs" | sha256sum -c -
image="pangolin-ipk-test:24.10.2-$arch"
if [ "$arch" = aarch64_cortex-a53 ]; then
	rootfs_work=$(mktemp -d "$cache/ipk-rootfs.XXXXXX")
	trap 'sudo rm -rf "$rootfs_work"' EXIT
	# The pinned image's SquashFS starts at 4 MiB. Nothing is flashed or booted.
	sudo unsquashfs -no-progress -o 4194304 -d "$rootfs_work/root" "$rootfs" >/dev/null
	sudo tar -C "$rootfs_work/root" -cf - . | docker import --platform "$platform" - "$image" >/dev/null
else
	docker import --platform "$platform" "$rootfs" "$image" >/dev/null
fi
docker run --rm --platform "$platform" \
	-v "$package_dir:/release:ro" \
	"$image" /bin/sh -exc '
		mkdir -p /var/lock /tmp/run
		opkg print-architecture | grep -F "arch $1 "
		# Offline mode prevents maintainer scripts loading kernel modules or
		# starting services. Dependencies still resolve against stock 24.10.2.
		opkg --offline-root / update
		opkg --offline-root / install /release/pangolin-cli_*.ipk /release/luci-app-pangolin_*.ipk
		opkg list-installed | grep -E "^(pangolin-cli|luci-app-pangolin|rpcd-mod-ucode|ucode-mod-uci|kmod-tun) "
		# opkg offline mode skips postinst. Exercise the CLI maintainer script
		# explicitly; its default configuration leaves the VPN disabled.
		sh /usr/lib/opkg/info/pangolin-cli.postinst configure
		# The version subcommand may append an online update notice.
		# Capture it first so a failed command still fails this test.
		version_output="$(PANGOLIN_CLI_DISABLE_UPDATE_CHECK=true pangolin version)"
		test "$(printf "%s\n" "$version_output" | sed -n 1p)" = 0.18.1
		ls -l /etc/config/pangolin | grep -E "^-rw-------[[:space:]]"
		for file in /usr/libexec/pangolin-*.uc /usr/share/rpcd/ucode/luci.pangolin; do
			ucode -c -o /tmp/check.ucb "$file"
		done
		! test -f /etc/pangolin/accounts.json
	' sh "$arch"
echo "OpenWrt 24.10.2 $arch IPK dependency resolution, installation and runtime checks passed."
