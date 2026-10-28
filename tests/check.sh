#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

for script in "$repo_root"/scripts/*.sh; do
	bash -n "$script"
done

sh -n "$repo_root/packages/newt/files/newt.init"
sh -n "$repo_root/packages/newt/files/newt-run"
sh -n "$repo_root/packages/newt/files/configure-newt"
sh -n "$repo_root/packages/newt/files/newt-service-action"
sh -n "$repo_root/packages/pangolin-cli/files/pangolin.init"
sh -n "$repo_root/packages/pangolin-cli/files/pangolin-client-run"
sh -n "$repo_root/packages/pangolin-cli/files/pangolin-client-watch"
sh -n "$repo_root/packages/pangolin-cli/files/pangolin-auth.init"
sh -n "$repo_root/packages/pangolin-cli/files/pangolin-auth-run"
sh -n "$repo_root/packages/luci-app-pangolin/root/usr/libexec/pangolin-auth-action"
sh -n "$repo_root/packages/luci-app-pangolin/root/usr/libexec/pangolin-package-action"
sh -n "$repo_root/packages/pangolin-cli/files/pangolin-network"
sh -n "$repo_root/packages/pangolin-cli/files/pangolin-service-action"
sh -n "$repo_root/packages/pangolin-cli/files/pangolin-site-run"
sh -n "$repo_root/examples/uci-defaults/90-newt"
sh -n "$repo_root/examples/uci-defaults/99-newt-from-feed"
sh -n "$repo_root/examples/uci-defaults/90-pangolin"
sh -n "$repo_root/examples/uci-defaults/99-pangolin-from-feed"
bash -n "$repo_root/tests/test_rpc_backends_openwrt.sh"
sh -n "$repo_root/tests/test_pangolin_client_integration.sh"
sh -n "$repo_root/tests/test_pangolin_auth_status.sh"
node --check "$repo_root/packages/luci-app-newt/htdocs/luci-static/resources/view/newt/overview.js"
node --check "$repo_root/packages/luci-app-pangolin/htdocs/luci-static/resources/view/pangolin/overview.js"
node "$repo_root/tests/test_pangolin_client_ui.mjs"
python3 "$repo_root/tests/test_package_files.py"
python3 "$repo_root/tests/test_release_version.py"
python3 "$repo_root/tests/test_pangolin_client_watch.py"
python3 -c 'import ast, pathlib, sys; ast.parse(pathlib.Path(sys.argv[1]).read_text())' \
	"$repo_root/tests/verify_artifacts.py"
"$repo_root/tests/test_pangolin_network.sh"

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
	"packages/pangolin-cli/Makefile"
	"packages/pangolin-cli/files/pangolin.config"
	"packages/pangolin-cli/files/newt-version"
	"packages/pangolin-cli/files/pangolin.init"
	"packages/pangolin-cli/files/pangolin-client-run"
	"packages/pangolin-cli/files/pangolin-client-watch"
	"packages/pangolin-cli/files/pangolin-dns"
	"packages/luci-app-pangolin/root/usr/libexec/pangolin-package-action"
	"packages/pangolin-cli/files/configure-pangolin"
	"packages/pangolin-cli/files/pangolin-network"
	"packages/pangolin-cli/files/pangolin-service-action"
	"packages/pangolin-cli/files/pangolin-site-run"
	"packages/pangolin-cli/files/pangolin-site-sync-credentials"
	"packages/pangolin-cli/files/dependency-patches/010-redact-newt-sensitive-logging.patch"
	"packages/pangolin-cli/files/dependency-patches/020-restrict-olm-api-socket.patch"
	"packages/pangolin-cli/files/dependency-patches/030-client-dns-control.patch"
	"packages/pangolin-cli/patches/010-use-patched-tunnel-modules.patch"
	"packages/pangolin-cli/patches/020-client-dns-control.patch"
	"packages/luci-app-pangolin/Makefile"
	"packages/luci-app-pangolin/root/usr/share/luci/menu.d/luci-app-pangolin.json"
	"packages/luci-app-pangolin/root/usr/share/rpcd/acl.d/luci-app-pangolin.json"
	"packages/luci-app-pangolin/root/usr/share/rpcd/ucode/luci.pangolin"
	"packages/luci-app-pangolin/htdocs/luci-static/resources/view/pangolin/overview.js"
	"scripts/build-newt-arm64.sh"
	"scripts/build-r5c-image.sh"
	"scripts/build-r5c-image-in-docker.sh"
	"scripts/verify-artifacts-in-docker.sh"
	"tests/verify_artifacts.py"
	"tests/test_pangolin_network.sh"
	"tests/test_rpc_backends_openwrt.sh"
	"tests/mocks/uci"
	"docs/IMAGEBUILDER.md"
	"docs/INSTALLING.md"
	"docs/NATIVE-MAIN-TESTING.md"
	"docs/MAINTAINER-HANDOFF.md"
	"examples/uci-defaults/99-newt-from-feed"
	"examples/uci-defaults/90-pangolin"
	"examples/uci-defaults/99-pangolin-from-feed"
	"LICENSE"
	"keys/openwrt-newt-public-key.pem"
)

for file in "${required_files[@]}"; do
	[ -s "$repo_root/$file" ] || {
		echo "Missing required file: $file" >&2
		exit 1
	}
done

[ -x "$repo_root/packages/luci-app-newt/root/usr/share/rpcd/ucode/luci.newt" ]
[ -x "$repo_root/packages/luci-app-pangolin/root/usr/share/rpcd/ucode/luci.pangolin" ]
[ -x "$repo_root/tests/test_rpc_backends_openwrt.sh" ]

jq -e . "$repo_root/packages/luci-app-newt/root/usr/share/luci/menu.d/luci-app-newt.json" >/dev/null
jq -e . "$repo_root/packages/luci-app-newt/root/usr/share/rpcd/acl.d/luci-app-newt.json" >/dev/null
jq -e . "$repo_root/packages/luci-app-pangolin/root/usr/share/luci/menu.d/luci-app-pangolin.json" >/dev/null
jq -e . "$repo_root/packages/luci-app-pangolin/root/usr/share/rpcd/acl.d/luci-app-pangolin.json" >/dev/null

grep -q 'PKG_VERSION:=1.18.1' "$repo_root/packages/newt/Makefile"
grep -q 'PKG_RELEASE:=3' "$repo_root/packages/newt/Makefile"
grep -q 'PKG_RELEASE:=4' "$repo_root/packages/luci-app-newt/Makefile"
grep -q 'PKG_HASH:=e3e66632a3ca2eeb950cb74e087ca837e7eee98a9e0816fcc1e4528a355ccd18' "$repo_root/packages/newt/Makefile"
grep -q 'CLI_VERSION:=0.18.1' "$repo_root/packages/pangolin-cli/Makefile"
grep -q 'PKG_HASH:=568fcbf62a1c485d8cec617c635ae5769ff5d6729bcf412a7f0d13efb3d498ad' "$repo_root/packages/pangolin-cli/Makefile"
grep -q 'OLM_HASH:=9de2a1b9daa21ce20b6642c2b948ab9616690800dbc0094835d2f711e3295f1a' "$repo_root/packages/pangolin-cli/Makefile"
grep -q 'option enabled' "$repo_root/packages/newt/files/newt.config"
grep -q 'procd_set_param respawn' "$repo_root/packages/newt/files/newt.init"
grep -q 'NEWT_SYSTEM_SUBSTRATE=CONTAINER' "$repo_root/packages/newt/files/newt.init"
grep -q 'Received authentication token' "$repo_root/packages/newt/patches/010-redact-sensitive-debug-logging.patch"
grep -q 'os.WriteFile(configPath, data, 0600)' "$repo_root/packages/newt/patches/010-redact-sensitive-debug-logging.patch"
grep -q 'github.com/fosrl/cli/internal/config.ManagedBy=openwrt' "$repo_root/packages/pangolin-cli/Makefile"
grep -qx '1\.18\.1' "$repo_root/packages/pangolin-cli/files/newt-version"
grep -q 'kmod-tun' "$repo_root/packages/pangolin-cli/Makefile"
grep -q 'uci -q set network.pangolin.device="$interface_name"' "$repo_root/packages/pangolin-cli/files/pangolin-network"
grep -q 'os.Chmod(socketPath, 0600)' "$repo_root/packages/pangolin-cli/files/dependency-patches/020-restrict-olm-api-socket.patch"
grep -q 'procd_open_instance site' "$repo_root/packages/pangolin-cli/files/pangolin.init"
grep -q 'instances?.\[role\]' "$repo_root/packages/luci-app-pangolin/root/usr/share/rpcd/ucode/luci.pangolin"
grep -q 'dns_configured_listener' "$repo_root/packages/luci-app-pangolin/root/usr/share/rpcd/ucode/luci.pangolin"
grep -q 'DNSListenAddr' "$repo_root/packages/pangolin-cli/files/dependency-patches/030-client-dns-control.patch"
grep -q 'PANGOLIN_CLI_CONFIG_DIR' "$repo_root/packages/pangolin-cli/patches/020-client-dns-control.patch"
if grep -Rq '\\x00]' \
	"$repo_root/packages/luci-app-newt/root/usr/share/rpcd/ucode" \
	"$repo_root/packages/luci-app-pangolin/root/usr/share/rpcd/ucode"; then
	echo 'ucode regex character classes must not use the unsupported \\x00 escape.' >&2
	exit 1
fi
grep -q 'site-started' "$repo_root/packages/pangolin-cli/files/pangolin.init"
grep -q 'site-started' "$repo_root/packages/pangolin-cli/files/pangolin-site-run"
grep -q 'mkdir -p "$HOME"' "$repo_root/packages/pangolin-cli/files/pangolin-site-run"
grep -q 'temporary_signing_key' "$repo_root/scripts/build-openwrt.sh"
grep -q 'package/pangolin-cli/compile NO_DEPS=1' "$repo_root/scripts/build-openwrt.sh"
grep -q -- '--prerelease --latest=false' "$repo_root/.github/workflows/build.yml"
if grep -Rq 'readCommand(\[' \
	"$repo_root/packages/luci-app-newt/root/usr/share/rpcd/ucode" \
	"$repo_root/packages/luci-app-pangolin/root/usr/share/rpcd/ucode"; then
	echo 'ucode fs.popen wrappers must receive command strings, not argv arrays.' >&2
	exit 1
fi
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
		"$repo_root/packages/newt/files/newt-service-action" \
		"$repo_root/packages/pangolin-cli/files/pangolin.init" \
		"$repo_root/packages/pangolin-cli/files/pangolin-client-run" \
		"$repo_root/packages/pangolin-cli/files/pangolin-client-watch" \
		"$repo_root/packages/pangolin-cli/files/configure-pangolin" \
		"$repo_root/packages/pangolin-cli/files/pangolin-network" \
		"$repo_root/packages/pangolin-cli/files/pangolin-service-action" \
		"$repo_root/packages/pangolin-cli/files/pangolin-site-run" \
		"$repo_root/examples/uci-defaults/90-newt" \
		"$repo_root/examples/uci-defaults/99-newt-from-feed" \
		"$repo_root/examples/uci-defaults/90-pangolin" \
		"$repo_root/examples/uci-defaults/99-pangolin-from-feed" \
		"$repo_root/tests/test_rpc_backends_openwrt.sh"
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

printf '%s\n' \
	"PANGOLIN_ENDPOINT='http://insecure.example.com'" \
	"NEWT_ID='test-id'" \
	"NEWT_SECRET='test-secret'" > "$test_dir/insecure-pangolin.env"
chmod 0600 "$test_dir/insecure-pangolin.env"
if "$repo_root/packages/pangolin-cli/files/configure-pangolin" "$test_dir/insecure-pangolin.env" >/dev/null 2>&1; then
	echo 'configure-pangolin accepted an insecure endpoint.' >&2
	exit 1
fi

printf '%s\n' \
	"PANGOLIN_ENDPOINT='https://'" \
	"NEWT_ID='test-id'" \
	"NEWT_SECRET='test-secret'" > "$test_dir/missing-host-pangolin.env"
chmod 0600 "$test_dir/missing-host-pangolin.env"
if "$repo_root/packages/pangolin-cli/files/configure-pangolin" "$test_dir/missing-host-pangolin.env" >/dev/null 2>&1; then
	echo 'configure-pangolin accepted an endpoint without a host.' >&2
	exit 1
fi

printf '%s\n' \
	"PANGOLIN_ENDPOINT='https://pangolin.example.com'" \
	"NEWT_ID='test-id'" > "$test_dir/incomplete-pangolin.env"
chmod 0600 "$test_dir/incomplete-pangolin.env"
if "$repo_root/packages/pangolin-cli/files/configure-pangolin" "$test_dir/incomplete-pangolin.env" >/dev/null 2>&1; then
	echo 'configure-pangolin accepted an incomplete ID/secret pair.' >&2
	exit 1
fi

printf '%s\n' \
	"PANGOLIN_ENDPOINT='https://pangolin.example.com'" \
	"NEWT_PROVISIONING_KEY='test-key'" \
	"NEWT_SITE_NAME='test-site'" \
	"NEWT_ID='test-id'" \
	"NEWT_SECRET='test-secret'" > "$test_dir/mixed-pangolin.env"
chmod 0600 "$test_dir/mixed-pangolin.env"
if "$repo_root/packages/pangolin-cli/files/configure-pangolin" "$test_dir/mixed-pangolin.env" >/dev/null 2>&1; then
	echo 'configure-pangolin accepted mixed authentication modes.' >&2
	exit 1
fi

echo 'Static checks passed.'
