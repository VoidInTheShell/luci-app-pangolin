#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
openwrt_version="${OPENWRT_VERSION:-25.12.5}"
imagebuilder_name="openwrt-imagebuilder-${openwrt_version}-rockchip-armv8.Linux-x86_64"
imagebuilder_archive="${imagebuilder_name}.tar.zst"
imagebuilder_sha256="013a8c95a5a8e838b04e18efe1d56e33ba93437d6242572a9a94bb03b843a9e3"
imagebuilder_url="https://downloads.openwrt.org/releases/${openwrt_version}/targets/rockchip/armv8/${imagebuilder_archive}"
cache_dir="${OPENWRT_CACHE_DIR:-${repo_root}/.cache}"
imagebuilder_dir="${OPENWRT_IMAGEBUILDER_DIR:-${cache_dir}/${imagebuilder_name}}"
archive_path="${cache_dir}/${imagebuilder_archive}"
package_dir="${repo_root}/dist/openwrt-${openwrt_version}/aarch64_generic"
output_dir="${package_dir}/images"

for command in curl find make sha256sum tar; do
	command -v "$command" >/dev/null 2>&1 || {
		echo "Required command not found: $command" >&2
		exit 1
	}
done

pangolin_apk="$(find "$package_dir" -maxdepth 1 -type f -name 'pangolin-cli-*.apk' -print -quit 2>/dev/null || true)"
luci_pangolin_apk="$(find "$package_dir" -maxdepth 1 -type f -name 'luci-app-pangolin-*.apk' -print -quit 2>/dev/null || true)"
[ -f "$pangolin_apk" ] && [ -f "$luci_pangolin_apk" ] || {
	echo 'Build the APKs first with ./scripts/build-openwrt.sh.' >&2
	exit 1
}

mkdir -p "$cache_dir" "$output_dir"

if [ ! -d "$imagebuilder_dir" ]; then
	if [ ! -f "$archive_path" ]; then
		echo "Downloading ${imagebuilder_archive}"
		curl -fL --retry 3 -o "$archive_path" "$imagebuilder_url"
	fi
	echo "${imagebuilder_sha256}  ${archive_path}" | sha256sum -c -
	echo 'Extracting OpenWrt ImageBuilder'
	tar --zstd -xf "$archive_path" -C "$cache_dir"
fi

[ -f "$imagebuilder_dir/Makefile" ] || {
	echo "Invalid ImageBuilder directory: $imagebuilder_dir" >&2
	exit 1
}

install -m 0644 "$pangolin_apk" "$imagebuilder_dir/packages/"
install -m 0644 "$luci_pangolin_apk" "$imagebuilder_dir/packages/"
if [ -f "$package_dir/openwrt-newt-public-key.pem" ]; then
	install -m 0644 "$package_dir/openwrt-newt-public-key.pem" "$imagebuilder_dir/keys/"
fi

files_args=()
if [ -n "${OPENWRT_IMAGE_FILES:-}" ]; then
	[ -d "$OPENWRT_IMAGE_FILES" ] || {
		echo "OPENWRT_IMAGE_FILES is not a directory: $OPENWRT_IMAGE_FILES" >&2
		exit 1
	}
	files_args=(FILES="$OPENWRT_IMAGE_FILES")
fi

make -C "$imagebuilder_dir" image \
	PROFILE=friendlyarm_nanopi-r5c \
	PACKAGES='luci luci-app-pangolin' \
	"${files_args[@]}"

mapfile -t images < <(find "$imagebuilder_dir/bin/targets/rockchip/armv8" \
	-maxdepth 1 -type f -name '*friendlyarm_nanopi-r5c-*-sysupgrade.img.gz' | sort)
[ "${#images[@]}" -gt 0 ] || {
	echo 'ImageBuilder did not produce a NanoPi R5C sysupgrade image.' >&2
	exit 1
}

# Do not retain images or manifests from an earlier package revision in the
# release directory when rebuilding incrementally.
rm -f "$output_dir"/*-newt-sysupgrade.img.gz \
	"$output_dir"/*-newt.manifest \
	"$output_dir"/*-pangolin-sysupgrade.img.gz \
	"$output_dir"/*-pangolin.manifest "$output_dir/images-sha256sums"

for image in "${images[@]}"; do
	base="$(basename "$image")"
	destination="${base%-sysupgrade.img.gz}-pangolin-sysupgrade.img.gz"
	install -m 0644 "$image" "$output_dir/$destination"
done

manifest="$(find "$imagebuilder_dir/bin/targets/rockchip/armv8" \
	-maxdepth 1 -type f -name '*friendlyarm_nanopi-r5c.manifest' -print -quit)"
[ -f "$manifest" ] || {
	echo 'ImageBuilder did not produce the NanoPi R5C package manifest.' >&2
	exit 1
}
grep -q '^pangolin-cli - 0\.18\.1-r2$' "$manifest" || {
	echo 'The R5C image manifest does not contain the expected Pangolin CLI package.' >&2
	exit 1
}
grep -q '^luci-app-pangolin - 1\.0\.0-r3$' "$manifest" || {
	echo 'The R5C image manifest does not contain the expected Pangolin LuCI package.' >&2
	exit 1
}
manifest_name="$(basename "$manifest" .manifest)-pangolin.manifest"
install -m 0644 "$manifest" "$output_dir/$manifest_name"

(
	cd "$output_dir"
	sha256sum ./*.img.gz ./*.manifest > images-sha256sums
)

echo "Image build complete: $output_dir"
ls -lh "$output_dir"
