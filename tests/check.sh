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
	"docs/INSTALLING.md"
	"docs/MAINTAINER-HANDOFF.md"
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
grep -q 'PKG_RELEASE:=2' "$repo_root/packages/newt/Makefile"
grep -q 'PKG_RELEASE:=2' "$repo_root/packages/luci-app-newt/Makefile"
grep -q 'PKG_HASH:=e3e66632a3ca2eeb950cb74e087ca837e7eee98a9e0816fcc1e4528a355ccd18' "$repo_root/packages/newt/Makefile"
grep -q 'option enabled' "$repo_root/packages/newt/files/newt.config"
grep -q 'procd_set_param respawn' "$repo_root/packages/newt/files/newt.init"
grep -q 'NEWT_SYSTEM_SUBSTRATE=CONTAINER' "$repo_root/packages/newt/files/newt.init"
grep -q 'Received authentication token' "$repo_root/packages/newt/patches/010-redact-sensitive-debug-logging.patch"
grep -q 'temporary_signing_key' "$repo_root/scripts/build-openwrt.sh"
grep -q "key_sha256='54a584f2a271bddb263225be0ed7e972fd506529adcc03993a8e50bac32c7546'" \
	"$repo_root/examples/uci-defaults/99-newt-from-feed"
grep -q 'procd_set_param command /usr/libexec/newt-feed-bootstrap' \
	"$repo_root/examples/uci-defaults/99-newt-from-feed"
grep -q 'Pangolin endpoint must be an HTTPS URL' \
	"$repo_root/packages/luci-app-newt/root/usr/share/rpcd/ucode/luci.newt"
openssl pkey -pubin -in "$repo_root/keys/openwrt-newt-public-key.pem" -noout
echo '54a584f2a271bddb263225be0ed7e972fd506529adcc03993a8e50bac32c7546  keys/openwrt-newt-public-key.pem' | \
	(cd "$repo_root" && sha256sum -c -) >/dev/null

if command -v shellcheck >/dev/null 2>&1; then
	shellcheck -S error \
		"$repo_root"/scripts/*.sh \
		"$repo_root/packages/newt/files/newt.init" \
		"$repo_root/packages/newt/files/newt-run" \
		"$repo_root/packages/newt/files/configure-newt" \
		"$repo_root/examples/uci-defaults/90-newt" \
		"$repo_root/examples/uci-defaults/99-newt-from-feed"
fi

test_dir="$(mktemp -d)"
trap 'rm -rf "$test_dir"' EXIT
printf '%s\n' \
	"PANGOLIN_ENDPOINT='http://insecure.example.com'" \
	"NEWT_ID='test-id'" \
	"NEWT_SECRET='test-secret'" > "$test_dir/insecure.env"
chmod 0600 "$test_dir/insecure.env"
if "$repo_root/packages/newt/files/configure-newt" "$test_dir/insecure.env" >/dev/null 2>&1; then
	echo 'configure-newt accepted an insecure endpoint.' >&2
	exit 1
fi

printf '%s\n' \
	"PANGOLIN_ENDPOINT='https://'" \
	"NEWT_ID='test-id'" \
	"NEWT_SECRET='test-secret'" > "$test_dir/missing-host.env"
chmod 0600 "$test_dir/missing-host.env"
if "$repo_root/packages/newt/files/configure-newt" "$test_dir/missing-host.env" >/dev/null 2>&1; then
	echo 'configure-newt accepted an endpoint without a host.' >&2
	exit 1
fi

printf '%s\n' \
	"PANGOLIN_ENDPOINT='https://pangolin.example.com'" \
	"NEWT_ID='test-id'" > "$test_dir/incomplete.env"
chmod 0600 "$test_dir/incomplete.env"
if "$repo_root/packages/newt/files/configure-newt" "$test_dir/incomplete.env" >/dev/null 2>&1; then
	echo 'configure-newt accepted an incomplete ID/secret pair.' >&2
	exit 1
fi

printf '%s\n' \
	"PANGOLIN_ENDPOINT='https://pangolin.example.com'" \
	"NEWT_PROVISIONING_KEY='test-key'" \
	"NEWT_SITE_NAME='test-site'" \
	"NEWT_ID='test-id'" \
	"NEWT_SECRET='test-secret'" > "$test_dir/mixed.env"
chmod 0600 "$test_dir/mixed.env"
if "$repo_root/packages/newt/files/configure-newt" "$test_dir/mixed.env" >/dev/null 2>&1; then
	echo 'configure-newt accepted mixed authentication modes.' >&2
	exit 1
fi

echo 'Static checks passed.'
