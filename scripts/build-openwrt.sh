#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
openwrt_version="${OPENWRT_VERSION:-25.12.5}"
openwrt_target="${OPENWRT_TARGET:-rockchip}"
openwrt_subtarget="${OPENWRT_SUBTARGET:-armv8}"
package_arch="${OPENWRT_PACKAGE_ARCH:-aarch64_generic}"
sdk_name="openwrt-sdk-${openwrt_version}-${openwrt_target}-${openwrt_subtarget}_gcc-14.3.0_musl.Linux-x86_64"
sdk_archive="${sdk_name}.tar.zst"
sdk_sha256="59194a023968398af64bfa7d8bc3eac322641f6dc9cdbade28a4d9dd41866eba"
sdk_url="https://downloads.openwrt.org/releases/${openwrt_version}/targets/${openwrt_target}/${openwrt_subtarget}/${sdk_archive}"
cache_dir="${OPENWRT_CACHE_DIR:-${repo_root}/.cache}"
sdk_dir="${OPENWRT_SDK_DIR:-${cache_dir}/${sdk_name}}"
archive_path="${cache_dir}/${sdk_archive}"
output_dir="${repo_root}/dist/openwrt-${openwrt_version}/${package_arch}"

for command in curl git make sha256sum tar; do
	command -v "$command" >/dev/null 2>&1 || {
		echo "Required command not found: $command" >&2
		exit 1
	}
done

if [ "${NEWT_USE_EXTERNAL_GO:-0}" = '1' ] || [ "${PANGOLIN_USE_EXTERNAL_GO:-0}" = '1' ]; then
	command -v go >/dev/null 2>&1 || {
		echo 'NEWT_USE_EXTERNAL_GO=1 requires Go 1.26 or newer in PATH.' >&2
		exit 1
	}
	go_version="$(go env GOVERSION)"
	case "$go_version" in
		go1.26.*|go1.2[7-9].*|go1.[3-9][0-9].*) ;;
		*)
			echo "Go 1.26 or newer is required; found ${go_version}." >&2
			exit 1
			;;
	esac
fi

mkdir -p "$cache_dir" "$output_dir"

if [ ! -d "$sdk_dir" ]; then
	if [ ! -f "$archive_path" ]; then
		echo "Downloading ${sdk_archive}"
		curl -fL --retry 3 -o "$archive_path" "$sdk_url"
	fi

	echo "${sdk_sha256}  ${archive_path}" | sha256sum -c -
	echo "Extracting OpenWrt SDK"
	tar --zstd -xf "$archive_path" -C "$cache_dir"
fi

[ -f "$sdk_dir/rules.mk" ] || {
	echo "Invalid SDK directory: $sdk_dir" >&2
	exit 1
}

cd "$sdk_dir"

# Never allow a release signing key copied into the SDK to persist in a local
# or CI cache. The source key remains outside the SDK and is copied only for
# the duration of this process.
temporary_signing_key="$sdk_dir/private-key.pem"
rm -f "$temporary_signing_key"
touch .config
sed -i \
	-e '/^CONFIG_SIGNED_PACKAGES=/d' \
	-e '/^# CONFIG_SIGNED_PACKAGES is not set$/d' \
	.config

if [ ! -f feeds/base.index ] || [ ! -f feeds/packages.index ] || [ ! -f feeds/luci.index ]; then
	./scripts/feeds update base packages luci
fi

# The release SDK keeps core package sources in its commit-pinned `base` feed.
# Installing luci-base recursively links only the core and packages-feed
# sources needed to stage headers and host tools; unrelated feeds remain
# deliberately omitted.
./scripts/feeds install ca-bundle luci-base rpcd-mod-ucode

link_package() {
	local name="$1"
	local source="$2"
	local destination="$sdk_dir/package/$name"

	if [ -L "$destination" ] && [ "$(readlink -f "$destination")" = "$(readlink -f "$source")" ]; then
		return
	fi
	if [ -e "$destination" ] || [ -L "$destination" ]; then
		echo "Refusing to replace existing SDK package path: $destination" >&2
		exit 1
	fi
	ln -s "$source" "$destination"
}

link_package newt "$repo_root/packages/newt"
link_package luci-app-newt "$repo_root/packages/luci-app-newt"
link_package pangolin-cli "$repo_root/packages/pangolin-cli"
link_package luci-app-pangolin "$repo_root/packages/luci-app-pangolin"

if [ -n "${OPENWRT_APK_PRIVATE_KEY_FILE:-}" ]; then
	command -v openssl >/dev/null 2>&1 || {
		echo 'Signing requires openssl.' >&2
		exit 1
	}
	derived_public_key="$sdk_dir/openwrt-newt-public-key.pem"
	openssl pkey -in "$OPENWRT_APK_PRIVATE_KEY_FILE" -pubout -out "$derived_public_key"
	if [ -f "$repo_root/keys/openwrt-newt-public-key.pem" ] && \
	   ! cmp -s "$derived_public_key" "$repo_root/keys/openwrt-newt-public-key.pem"; then
		echo 'The signing key does not match keys/openwrt-newt-public-key.pem.' >&2
		exit 1
	fi
	install -m 0600 "$OPENWRT_APK_PRIVATE_KEY_FILE" "$temporary_signing_key"
	trap 'rm -f "$temporary_signing_key"' EXIT
	echo 'CONFIG_SIGNED_PACKAGES=y' >> .config
else
	echo '# CONFIG_SIGNED_PACKAGES is not set' >> .config
fi

# The release SDK carries liblucihttp-lua=m in its seed configuration while
# intentionally omitting the legacy liblua development package. This project
# uses LuCI's ucode runtime exclusively, so prevent CMake from building the
# unneeded Lua binding and its unavailable header dependency.
sed -i \
	-e '/^CONFIG_PACKAGE_liblucihttp-lua=/d' \
	-e '/^# CONFIG_PACKAGE_liblucihttp-lua is not set$/d' \
	.config
echo '# CONFIG_PACKAGE_liblucihttp-lua is not set' >> .config

# SDK seed configurations enable CONFIG_ALL, CONFIG_ALL_NONSHARED, and
# CONFIG_ALL_KMODS so arbitrary out-of-tree packages can be built. This project
# selects its dependencies explicitly; leaving those umbrellas enabled makes
# package/kernel/linux package every module (extremely slow under x86
# emulation on Apple Silicon).
sed -i \
	-e '/^CONFIG_ALL=/d' \
	-e '/^# CONFIG_ALL is not set$/d' \
	-e '/^CONFIG_ALL_NONSHARED=/d' \
	-e '/^# CONFIG_ALL_NONSHARED is not set$/d' \
	-e '/^CONFIG_ALL_KMODS=/d' \
	-e '/^# CONFIG_ALL_KMODS is not set$/d' \
	-e '/^CONFIG_PACKAGE_kmod-/d' \
	-e '/^# CONFIG_PACKAGE_kmod-/d' \
	.config
echo '# CONFIG_ALL is not set' >> .config
echo '# CONFIG_ALL_NONSHARED is not set' >> .config
echo '# CONFIG_ALL_KMODS is not set' >> .config

# Explicitly select every package owned by this repository. Invoking a
# package/<name>/compile target does not guarantee that OpenWrt will emit an
# APK when an SDK cache was created before that package existed. Keeping the
# selections here makes fresh SDKs and restored CI caches behave identically.
for package_name in newt luci-app-newt pangolin-cli luci-app-pangolin; do
	sed -i \
		-e "/^CONFIG_PACKAGE_${package_name}=/d" \
		-e "/^# CONFIG_PACKAGE_${package_name} is not set$/d" \
		.config
	echo "CONFIG_PACKAGE_${package_name}=m" >> .config
done

make defconfig
make package/newt/compile
make package/luci-app-newt/compile
# The package declares kmod-tun as a runtime dependency, but the release SDK
# does not need to rebuild OpenWrt's official kernel package to compile this
# static Go binary. Without NO_DEPS the kernel package target emits every
# target-default module, which is both unnecessary and prohibitively slow
# under x86 emulation on Apple Silicon. ImageBuilder and apk resolve the exact
# release-matched kmod-tun from the official OpenWrt repository.
make package/pangolin-cli/compile NO_DEPS=1
make package/luci-app-pangolin/compile NO_DEPS=1
make package/index

newt_apk="$(find bin/packages -type f -name 'newt-*.apk' -print -quit)"
luci_apk="$(find bin/packages -type f -name 'luci-app-newt-*.apk' -print -quit)"
pangolin_apk="$(find bin/packages -type f -name 'pangolin-cli-*.apk' -print -quit)"
luci_pangolin_apk="$(find bin/packages -type f -name 'luci-app-pangolin-*.apk' -print -quit)"
host_apk="$sdk_dir/staging_dir/host/bin/apk"

[ -n "$newt_apk" ] && [ -f "$newt_apk" ] || {
	echo 'Newt APK was not produced.' >&2
	exit 1
}
[ -n "$luci_apk" ] && [ -f "$luci_apk" ] || {
	echo 'LuCI APK was not produced.' >&2
	exit 1
}
[ -n "$pangolin_apk" ] && [ -f "$pangolin_apk" ] || {
	echo 'Pangolin CLI APK was not produced.' >&2
	exit 1
}
[ -n "$luci_pangolin_apk" ] && [ -f "$luci_pangolin_apk" ] || {
	echo 'Pangolin LuCI APK was not produced.' >&2
	exit 1
}
[ -x "$host_apk" ] || {
	echo "OpenWrt host apk tool was not produced: $host_apk" >&2
	exit 1
}

# The SDK may retain an earlier development signature on cached package files.
# Normalize every release artifact to the configured stable key instead of
# trusting incremental package-signing state.
if [ -n "${OPENWRT_APK_PRIVATE_KEY_FILE:-}" ]; then
	for package_file in "$newt_apk" "$luci_apk" "$pangolin_apk" "$luci_pangolin_apk"; do
		"$host_apk" adbsign --allow-untrusted --reset-signatures \
			--sign-key "$sdk_dir/private-key.pem" \
			"$package_file"
	done
fi

# Prevent an incremental local build from publishing superseded package
# revisions alongside the current pair. CI starts clean, but releases must be
# equally deterministic when reproduced from a developer workstation.
rm -f "$output_dir"/newt-*.apk "$output_dir"/luci-app-newt-*.apk \
	"$output_dir"/pangolin-cli-*.apk "$output_dir"/luci-app-pangolin-*.apk
install -m 0644 "$newt_apk" "$output_dir/"
install -m 0644 "$luci_apk" "$output_dir/"
install -m 0644 "$pangolin_apk" "$output_dir/"
install -m 0644 "$luci_pangolin_apk" "$output_dir/"

sign_args=()
if [ -n "${OPENWRT_APK_PRIVATE_KEY_FILE:-}" ]; then
	sign_args=(--sign-key "$sdk_dir/private-key.pem")
fi

rm -f "$output_dir/packages.adb" "$output_dir/index.json" "$output_dir/openwrt-newt-public-key.pem"
(
	cd "$output_dir"
	"$host_apk" mkndx \
		--root "$sdk_dir" \
		--keys-dir "$sdk_dir" \
		--allow-untrusted \
		"${sign_args[@]}" \
		--output packages.adb \
		*.apk
	"$host_apk" adbdump --format json packages.adb | \
		"$sdk_dir/scripts/make-index-json.py" -f apk -a "$package_arch" - > index.json
)

if [ -n "${OPENWRT_APK_PRIVATE_KEY_FILE:-}" ]; then
	install -m 0644 "$sdk_dir/openwrt-newt-public-key.pem" "$output_dir/openwrt-newt-public-key.pem"
fi

(
	cd "$output_dir"
	sha256sum ./*.apk ./packages.adb ./index.json > packages-sha256sums
	if [ -f openwrt-newt-public-key.pem ]; then
		sha256sum ./openwrt-newt-public-key.pem >> packages-sha256sums
	fi
)

echo "Build complete: $output_dir"
ls -lh "$output_dir"
