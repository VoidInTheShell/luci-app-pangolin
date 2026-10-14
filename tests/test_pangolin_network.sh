#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_dir="$(mktemp -d)"
trap 'rm -rf "$test_dir"' EXIT
db="$test_dir/uci.db"

cat > "$db" <<'EOF'
pangolin.main.enabled=1
pangolin.main.native_main=1
pangolin.main.manage_network=1
pangolin.main.interface_main=pangolin
EOF

MOCK_UCI_DB="$db" \
PANGOLIN_NO_RELOAD=1 \
PATH="$repo_root/tests/mocks:$PATH" \
	"$repo_root/packages/pangolin-cli/files/pangolin-network" sync

grep -q '^network.pangolin=interface$' "$db"
grep -q '^network.pangolin.device=pangolin$' "$db"
grep -q '^firewall.pangolin=zone$' "$db"
grep -q '^firewall.pangolin.input=ACCEPT$' "$db"
grep -q '^firewall.pangolin.output=ACCEPT$' "$db"
grep -q '^firewall.pangolin.forward=REJECT$' "$db"

# A later sync must preserve an administrator's zone policy edits.
MOCK_UCI_DB="$db" PATH="$repo_root/tests/mocks:$PATH" \
	uci -q set firewall.pangolin.input=REJECT
MOCK_UCI_DB="$db" PATH="$repo_root/tests/mocks:$PATH" \
	uci -q set pangolin.main.interface_main=pangolin0
MOCK_UCI_DB="$db" PANGOLIN_NO_RELOAD=1 PATH="$repo_root/tests/mocks:$PATH" \
	"$repo_root/packages/pangolin-cli/files/pangolin-network" sync

grep -q '^firewall.pangolin.input=REJECT$' "$db"
grep -q '^network.pangolin.device=pangolin0$' "$db"

# The reliable default userspace site mode must not create a host interface.
: > "$db"
cat > "$db" <<'EOF'
pangolin.main.enabled=1
pangolin.main.native_main=0
pangolin.main.manage_network=1
EOF
MOCK_UCI_DB="$db" PANGOLIN_NO_RELOAD=1 PATH="$repo_root/tests/mocks:$PATH" \
	"$repo_root/packages/pangolin-cli/files/pangolin-network" sync
if grep -q '^network.pangolin=' "$db"; then
	echo 'Userspace site mode unexpectedly created a Pangolin TUN interface.' >&2
	exit 1
fi

# Disabling OpenWrt integration must also leave a fresh configuration alone.
: > "$db"
cat > "$db" <<'EOF'
pangolin.main.enabled=1
pangolin.main.native_main=1
pangolin.main.manage_network=0
EOF
MOCK_UCI_DB="$db" PANGOLIN_NO_RELOAD=1 PATH="$repo_root/tests/mocks:$PATH" \
	"$repo_root/packages/pangolin-cli/files/pangolin-network" sync
if grep -q '^network.pangolin=' "$db"; then
	echo 'Disabled network integration unexpectedly created an interface.' >&2
	exit 1
fi

echo 'Pangolin network integration tests passed.'
