#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
openwrt_version="${OPENWRT_VERSION:-25.12.5}"
sdk_name="openwrt-sdk-${openwrt_version}-rockchip-armv8_gcc-14.3.0_musl.Linux-x86_64"
artifacts="${repo_root}/dist/openwrt-${openwrt_version}/aarch64_generic"
verify_root="${repo_root}/dist/verify-root"
host_uid="$(id -u)"
host_gid="$(id -g)"

if [ -d "${repo_root}/.cache/${sdk_name}" ]; then
	cache_mount=( -v "${repo_root}/.cache:/openwrt-cache" )
else
	cache_mount=( -v openwrt-newt-sdk-cache:/openwrt-cache )
fi

newt_apk="${artifacts}/newt-1.18.1-r2.apk"
luci_apk="${artifacts}/luci-app-newt-1.0.0-r2.apk"

for file in "$newt_apk" "$luci_apk" "$artifacts/packages.adb" "$artifacts/index.json"; do
	[ -s "$file" ] || {
		echo "Missing build artifact: $file" >&2
		exit 1
	}
done

rm -rf "$verify_root"
mkdir -p "$verify_root/newt-root" "$verify_root/luci-root"
trap 'rm -rf "$verify_root"' EXIT

if [ -f "$artifacts/openwrt-newt-public-key.pem" ]; then
	verify_args='--keys-dir /workspace/keys'
else
	verify_args='--allow-untrusted'
fi

docker run --rm --platform linux/amd64 \
	"${cache_mount[@]}" \
	-v "$repo_root:/workspace" \
	python:3.11-slim \
	bash -lc "set -euo pipefail
sdk=/openwrt-cache/${sdk_name}
apk=\"\$sdk/staging_dir/host/bin/apk\"
\"\$apk\" verify ${verify_args} \
  /workspace/dist/openwrt-${openwrt_version}/aarch64_generic/newt-1.18.1-r2.apk \
  /workspace/dist/openwrt-${openwrt_version}/aarch64_generic/luci-app-newt-1.0.0-r2.apk \
  /workspace/dist/openwrt-${openwrt_version}/aarch64_generic/packages.adb
\"\$apk\" adbdump --format json \
  /workspace/dist/openwrt-${openwrt_version}/aarch64_generic/newt-1.18.1-r2.apk \
  > /workspace/dist/verify-root/newt.json
\"\$apk\" adbdump --format json \
  /workspace/dist/openwrt-${openwrt_version}/aarch64_generic/luci-app-newt-1.0.0-r2.apk \
  > /workspace/dist/verify-root/luci.json
cp /workspace/dist/openwrt-${openwrt_version}/aarch64_generic/index.json \
  /workspace/dist/verify-root/feed.json
\"\$apk\" extract ${verify_args} \
  --destination /workspace/dist/verify-root/newt-root \
  /workspace/dist/openwrt-${openwrt_version}/aarch64_generic/newt-1.18.1-r2.apk
\"\$apk\" extract ${verify_args} \
  --destination /workspace/dist/verify-root/luci-root \
  /workspace/dist/openwrt-${openwrt_version}/aarch64_generic/luci-app-newt-1.0.0-r2.apk
chown -R ${host_uid}:${host_gid} /workspace/dist/verify-root"

python3 "$repo_root/tests/verify_artifacts.py" "$verify_root"

version_output="$(docker run --rm --platform linux/arm64 \
	-v "$verify_root/newt-root:/rootfs:ro" \
	debian:bookworm-slim /rootfs/usr/bin/newt --version)"
[ "$version_output" = 'Newt version 1.18.1' ] || {
	echo "Unexpected ARM64 version output: $version_output" >&2
	exit 1
}

docker run --rm --platform linux/arm64 \
	"${cache_mount[@]}" \
	-v "$repo_root:/workspace:ro" \
	debian:bookworm-slim \
	bash -lc "set -euo pipefail
sdk=/openwrt-cache/${sdk_name}
root=\"\$sdk/staging_dir/target-aarch64_generic_musl/root-rockchip\"
\"\$root/lib/ld-musl-aarch64.so.1\" \
  --library-path \"\$root/usr/lib:\$root/lib\" \
  \"\$root/usr/bin/ucode\" \
  -L \"\$root/usr/lib/ucode\" -c -o /tmp/luci.newt.uc \
  /workspace/packages/luci-app-newt/root/usr/share/rpcd/ucode/luci.newt
test -s /tmp/luci.newt.uc"

echo 'Signed feed, APK payload, ARM64 execution, and ucode compilation checks passed.'
