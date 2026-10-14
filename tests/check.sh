#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

for script in "$repo_root"/scripts/*.sh; do
	bash -n "$script"
done

sh -n "$repo_root/packages/newt/files/newt.init"
sh -n "$repo_root/packages/newt/files/newt-run"
sh -n "$repo_root/packages/newt/files/configure-newt"
sh -n "$repo_root/examples/uci-defaults/90-newt"
sh -n "$repo_root/examples/uci-defaults/99-newt-from-feed"
node --check "$repo_root/packages/luci-app-newt/htdocs/luci-static/resources/view/newt/overview.js"
python3 -c 'import ast, pathlib, sys; ast.parse(pathlib.Path(sys.argv[1]).read_text())' \
	"$repo_root/tests/verify_artifacts.py"

required_files=(
	"packages/newt/Makefile"
	"packages/newt/files/newt.config"
	"packages/newt/files/newt.init"
	"packages/newt/files/newt-run"
	"packages/newt/files/newt-sync-credentials"
	"packages/newt/files/configure-newt"
	"packages/newt/patches/010-redact-sensitive-debug-logging.patch"
	"packages/luci-app-newt/Makefile"
	"packages/luci-app-newt/root/usr/share/luci/menu.d/luci-app-newt.json"
	"packages/luci-app-newt/root/usr/share/rpcd/acl.d/luci-app-newt.json"
	"packages/luci-app-newt/root/usr/share/rpcd/ucode/luci.newt"
	"packages/luci-app-newt/htdocs/luci-static/resources/view/newt/overview.js"
	"scripts/build-newt-arm64.sh"
	"scripts/build-r5c-image.sh"
	"scripts/build-r5c-image-in-docker.sh"
	"scripts/verify-artifacts-in-docker.sh"
	"tests/verify_artifacts.py"
	"docs/IMAGEBUILDER.md"
	"examples/uci-defaults/99-newt-from-feed"
	"LICENSE"
	"keys/openwrt-newt-public-key.pem"
)

for file in "${required_files[@]}"; do
	[ -s "$repo_root/$file" ] || {
		echo "Missing required file: $file" >&2
		exit 1
	}
done

jq -e . "$repo_root/packages/luci-app-newt/root/usr/share/luci/menu.d/luci-app-newt.json" >/dev/null
jq -e . "$repo_root/packages/luci-app-newt/root/usr/share/rpcd/acl.d/luci-app-newt.json" >/dev/null

grep -q 'PKG_VERSION:=1.18.1' "$repo_root/packages/newt/Makefile"
grep -q 'PKG_HASH:=e3e66632a3ca2eeb950cb74e087ca837e7eee98a9e0816fcc1e4528a355ccd18' "$repo_root/packages/newt/Makefile"
grep -q 'option enabled' "$repo_root/packages/newt/files/newt.config"
grep -q 'procd_set_param respawn' "$repo_root/packages/newt/files/newt.init"
grep -q 'NEWT_SYSTEM_SUBSTRATE=CONTAINER' "$repo_root/packages/newt/files/newt.init"
grep -q 'Received authentication token' "$repo_root/packages/newt/patches/010-redact-sensitive-debug-logging.patch"
grep -q 'temporary_signing_key' "$repo_root/scripts/build-openwrt.sh"
openssl pkey -pubin -in "$repo_root/keys/openwrt-newt-public-key.pem" -noout

echo 'Static checks passed.'
