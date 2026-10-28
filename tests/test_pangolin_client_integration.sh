#!/bin/sh
# Run only inside the disposable OpenWrt container, never on a real router.
set -eu
[ "${PANGOLIN_DISPOSABLE_TEST:-}" = 1 ] || {
	echo 'Run via tests/test_rpc_backends_openwrt.sh (disposable container only).' >&2
	exit 1
}
export PANGOLIN_NO_RELOAD=1
helper=/usr/libexec/pangolin-client-integration
state=/etc/pangolin/integration-backup.json

fail() { echo "$*" >&2; exit 1; }
expect_failure() {
	if "$helper" "$1" >/tmp/integration-test-error 2>&1; then
		fail "Unexpected success: $1"
	fi
	grep -q "$2" /tmp/integration-test-error || {
		cat /tmp/integration-test-error >&2
		fail "Missing diagnostic: $2"
	}
}
config_hash() { cat /etc/config/network /etc/config/firewall | sha256sum; }

uci set pangolin.main.role=client
uci set pangolin.main.enabled=1
uci set pangolin.main.client_firewall=1
uci set pangolin.main.subnet_router=1
uci set pangolin.main.nikki_bypass=0
uci commit pangolin
mkdir -p /var/run/pangolin
touch /var/run/pangolin/client-active
# Docker's cgroup layout is not OpenWrt's procd layout. Bind a private fixture
# over the container's cgroup mount; do not write to real host cgroup files.
mkdir -p /tmp/pangolin-test-cgroups/services/pangolin/client
: > /tmp/pangolin-test-cgroups/services/pangolin/cgroup.procs
printf '%s\n' "$$" > /tmp/pangolin-test-cgroups/services/pangolin/client/cgroup.procs
mount -o bind /tmp/pangolin-test-cgroups /sys/fs/cgroup

"$helper" sync
[ "$(uci get network.pangolin_client.proto)" = none ]
[ "$(uci get firewall.pangolin_client.name)" = pg_client ]
[ "$(uci get firewall.pangolin_client_lan.dest)" = pg_client ]
ucode -e 'import { stat } from "fs"; if ((stat(ARGV[0]).mode & 0777) != 0600) exit(1);' "$state"
[ "$(jsonfilter -i "$state" -e '@[*].config' | wc -l)" -eq 3 ]
before="$(config_hash)"
state_before="$(sha256sum "$state")"
"$helper" sync
[ "$(config_hash)" = "$before" ]
[ "$(sha256sum "$state")" = "$state_before" ]
[ ! -e "$state.tmp" ]

# A failed temporary write must leave the previous ownership journal intact.
mkdir "$state.tmp"
expect_failure sync 'Unable to save integration rollback state'
[ "$(sha256sum "$state")" = "$state_before" ]
[ "$(config_hash)" = "$before" ]
rmdir "$state.tmp"

# Losing ownership must not cause silent adoption on the regular watch loop.
rm "$state"
expect_failure sync 'Refusing to replace existing network.pangolin_client'
[ ! -e "$state" ]
[ "$(config_hash)" = "$before" ]

# Recovery checks ALL candidates first; even an extra key blocks all adoption.
uci set firewall.pangolin_client.extra=administrator
uci commit firewall
mismatch_before="$(config_hash)"
expect_failure recover 'Refusing to recover mismatched firewall.pangolin_client'
[ ! -e "$state" ]
[ "$(config_hash)" = "$mismatch_before" ]
uci delete firewall.pangolin_client.extra
uci commit firewall

# List/scalar mismatches are not equivalent even when they print the same text.
uci delete firewall.pangolin_client.network
uci set firewall.pangolin_client.network=pangolin_client
uci commit firewall
expect_failure recover 'Refusing to recover mismatched firewall.pangolin_client'
[ ! -e "$state" ]
uci delete firewall.pangolin_client.network
uci add_list firewall.pangolin_client.network=pangolin_client
uci commit firewall

# Do not commit or take ownership of the administrator's staged changes.
uci set network.pangolin_client.device=pending
expect_failure recover 'Save pending network changes'
[ ! -e "$state" ]
[ "$(uci get network.pangolin_client.device)" = pending ]
uci revert network

# Exact-match recovery records ownership WITHOUT rewriting network/firewall.
before="$(config_hash)"
"$helper" recover
[ "$(config_hash)" = "$before" ]
[ "$(jsonfilter -i "$state" -e '@[*].config' | wc -l)" -eq 3 ]
"$helper" sync

# An invalid journal is never discarded or overwritten, even by recovery.
cp "$state" /tmp/integration-test-state
printf 'broken journal\n' > "$state"
expect_failure recover 'Invalid integration rollback state'
grep -q 'broken journal' "$state"
cp /tmp/integration-test-state "$state"

# Outside edits remain protected after adoption, including during rollback.
uci set firewall.pangolin_client.extra=administrator
uci commit firewall
expect_failure sync 'was edited outside Pangolin'
[ "$(uci get firewall.pangolin_client.extra)" = administrator ]
expect_failure restore 'was edited outside Pangolin'
[ "$(uci get firewall.pangolin_client.extra)" = administrator ]
[ -f "$state" ]
uci delete firewall.pangolin_client.extra
uci commit firewall
"$helper" restore
[ ! -e "$state" ]
if uci -q get firewall.pangolin_client >/dev/null; then fail 'Rollback left an owned zone.'; fi

# Stop followed by sync can create a clean ownership record again.
"$helper" sync
"$helper" stop-client
[ ! -e "$state" ]
if uci -q get network.pangolin_client >/dev/null; then fail 'Stop left an owned network.'; fi
"$helper" sync

# A live watcher in the parent cgroup cannot impersonate an exited client.
: > /sys/fs/cgroup/services/pangolin/client/cgroup.procs
printf '%s\n' "$$" > /sys/fs/cgroup/services/pangolin/cgroup.procs
"$helper" sync
[ ! -e "$state" ]
if uci -q get network.pangolin_client >/dev/null; then fail 'Inactive client left rules installed.'; fi
printf '%s\n' "$$" > /sys/fs/cgroup/services/pangolin/client/cgroup.procs
"$helper" sync
"$helper" restore
umount /sys/fs/cgroup
rm -f /var/run/pangolin/client-active /tmp/integration-test-error /tmp/integration-test-state

echo 'Pangolin client integration recovery and ownership regressions passed.'
