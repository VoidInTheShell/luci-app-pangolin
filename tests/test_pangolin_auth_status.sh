#!/bin/sh
# Synthetic accounts only; this runs in the disposable OpenWrt test container.
set -eu
[ "${PANGOLIN_DISPOSABLE_TEST:-}" = 1 ] || exit 1
uci set pangolin.main.endpoint=https://example.test
uci commit pangolin
umask 077
mkdir -p /etc/pangolin/client /var/run/pangolin-auth
cat > /etc/pangolin/client/accounts.json <<'EOF'
{"activeUserId":"test","accounts":{"test":{"host":"https://example.test","sessionToken":"test-session","olmCredentials":{"secret":"test-secret"},"orgId":"test-org"}}}
EOF
check() {
	result="$(ubus call luci.pangolin get_auth_status '{}')"
	[ "$(printf '%s' "$result" | jsonfilter -e '@.authenticated')" = "$1" ]
	[ "$(printf '%s' "$result" | jsonfilter -e '@.state')" = "$2" ]
	# Public RPC data must not leak the synthetic credentials either.
	if printf '%s' "$result" | grep -q 'test-session\|test-secret'; then exit 1; fi
}
for state in error expired idle; do
	printf '{"State":"%s","Error":"old failure"}\n' "$state" > /var/run/pangolin-auth/status.json
	check true authenticated
	[ "$(printf '%s' "$result" | jsonfilter -e '@.error')" = '' ]
done
# No live login worker: stale starting/pending states must also resolve to the
# already authenticated account rather than becoming an error notification.
printf '{"State":"starting"}\n' > /var/run/pangolin-auth/status.json
check true authenticated

# A real, explicit reauthentication flow must still expose the new pairing.
ubus call service set '{"name":"pangolin-auth","instances":{"login":{"command":["/bin/sleep","3600"]}}}' >/dev/null
running=false
for _attempt in $(seq 1 20); do
	running="$(ubus call service list '{"name":"pangolin-auth"}' | jsonfilter -e '@["pangolin-auth"].instances.login.running')"
	[ "$running" != true ] || break
	sleep 1
done
[ "$running" = true ]
printf '{"State":"starting"}\n' > /var/run/pangolin-auth/status.json
check true starting
expires="$(( $(date +%s) + 120 ))"
printf '{"State":"pending","URL":"https://example.test/auth/login/device?code=EXAMPLE","Code":"EXAMPLE","ExpiresAt":%s}\n' "$expires" > /var/run/pangolin-auth/status.json
check true pending
[ "$(printf '%s' "$result" | jsonfilter -e '@.code')" = EXAMPLE ]
ubus call service delete '{"name":"pangolin-auth"}' >/dev/null

# Credentials for a different endpoint must not suppress a genuine error.
uci set pangolin.main.endpoint=https://different.example.test
uci commit pangolin
printf '{"State":"error","Error":"login failed"}\n' > /var/run/pangolin-auth/status.json
check false error
[ -n "$(printf '%s' "$result" | jsonfilter -e '@.error')" ]
uci set pangolin.main.endpoint=https://example.test
uci commit pangolin
rm /etc/pangolin/client/accounts.json
check false error
rm /var/run/pangolin-auth/status.json

echo 'Pangolin authenticated/stale pairing status regressions passed.'
