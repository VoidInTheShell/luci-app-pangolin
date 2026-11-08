#!/bin/sh
# Real OpenWrt UCI/functions/ucode and the auth worker; synthetic CLI/services.
set -eu
[ "${PANGOLIN_DISPOSABLE_TEST:-}" = 1 ] || exit 1
mkdir -p /etc/pangolin/client /var/run/pangolin-auth /tmp/pangolin-auth-test
export TEST_AUTH_EVENTS=/tmp/pangolin-auth-test/events
export TEST_AUTH_RESULT=success TEST_RESTART_FAIL=0

cat > /usr/bin/pangolin <<'EOF'
#!/bin/sh
set -eu
case "$TEST_AUTH_RESULT" in
	fail) exit 1 ;;
	cancel) rm -f /var/run/pangolin-auth/active ;;
	endpoint) uci set pangolin.main.endpoint=https://changed.example.test; uci commit pangolin ;;
	role) uci set pangolin.main.role=site; uci commit pangolin ;;
	mode) uci set pangolin.main.client_auth=machine; uci commit pangolin ;;
esac
cat > /etc/pangolin/client/accounts.json <<'JSON'
{"activeUserId":"test","accounts":{"test":{"host":"https://example.test","sessionToken":"synthetic-session","olmCredentials":{"secret":"synthetic-secret"}}}}
JSON
case "$TEST_AUTH_RESULT" in
	incomplete) printf '%s\n' '{"activeUserId":"test","accounts":{"test":{"host":"https://example.test","sessionToken":"synthetic-session"}}}' > /etc/pangolin/client/accounts.json ;;
	lowercase) printf '%s\n' '{"activeuserid":"test","accounts":{"test":{"host":"https://example.test","sessiontoken":"synthetic-session","olmcredentials":{"secret":"synthetic-secret"}}}}' > /etc/pangolin/client/accounts.json ;;
	wrong-account) printf '%s\n' '{"activeUserId":"other","accounts":{"test":{"host":"https://example.test","sessionToken":"synthetic-session","olmCredentials":{"secret":"synthetic-secret"}}}}' > /etc/pangolin/client/accounts.json ;;
esac
printf '%s\n' '{"State":"authenticated"}' > /var/run/pangolin-auth/status.json
EOF
cat > /etc/init.d/pangolin <<'EOF'
#!/bin/sh
set -eu
printf '%s:%s\n' "$1" "$(uci -q get pangolin.main.enabled)" >> "$TEST_AUTH_EVENTS"
[ "$1" != restart ] || [ "$TEST_RESTART_FAIL" != 1 ]
EOF
cat > /etc/init.d/pangolin-auth <<'EOF'
#!/bin/sh
set -eu
if [ "$1" = restart ]; then
	[ "${2:-}" = pair ]
	printf '%s\n' auth-restart-pair >> "$TEST_AUTH_EVENTS"
	exit 0
fi
printf '%s\n' auth-stop >> "$TEST_AUTH_EVENTS"
rm -f /var/run/pangolin-auth/active /var/run/pangolin-auth/attempt /var/run/pangolin-auth/status.json
EOF
cat > /usr/libexec/pangolin-client-integration <<'EOF'
#!/bin/sh
printf '%s\n' "$1" >> "$TEST_AUTH_EVENTS"
EOF
chmod 0755 /usr/bin/pangolin /etc/init.d/pangolin /etc/init.d/pangolin-auth /usr/libexec/pangolin-client-integration

pair() {
	uci set pangolin.main.endpoint=https://example.test
	uci set pangolin.main.role=client
	uci set pangolin.main.client_auth=web
	uci set pangolin.main.enabled="$1"
	uci commit pangolin
	printf '%s\n' '{"State":"starting"}' > /var/run/pangolin-auth/status.json
	touch /var/run/pangolin-auth/active
	: > "$TEST_AUTH_EVENTS"
	result=0
	/usr/libexec/pangolin-auth-run || result=$?
	[ ! -f /var/run/pangolin-auth/active ]
	[ "$(tail -n 1 "$TEST_AUTH_EVENTS")" = stop-auth ]
}
check_started() {
	[ "$result" = 0 ]
	[ "$(uci -q get pangolin.main.enabled)" = 1 ]
	[ "$(cat "$TEST_AUTH_EVENTS")" = "$(printf 'sync\nrestart:1\nstop-auth')" ]
	[ "$(jsonfilter -i /var/run/pangolin-auth/status.json -e '@.State')" = authenticated ]
}

# Pairing must be explicitly requested through the init service.
: > "$TEST_AUTH_EVENTS"
/usr/libexec/pangolin-auth-action start
[ "$(cat "$TEST_AUTH_EVENTS")" = auth-restart-pair ]

# First installation, reauthentication while enabled, then logout + pairing.
pair 0
check_started
pair 1
check_started
TEST_AUTH_RESULT=lowercase
pair 0
check_started
TEST_AUTH_RESULT=success
: > "$TEST_AUTH_EVENTS"
/usr/libexec/pangolin-auth-action logout
[ "$(cat "$TEST_AUTH_EVENTS")" = "$(printf 'auth-stop\nstop:1')" ]
[ ! -f /etc/pangolin/client/accounts.json ]
pair 1
check_started

# Old saved credentials must never turn a failed/cancelled login into a restart.
for outcome in fail cancel endpoint role mode incomplete wrong-account; do
	TEST_AUTH_RESULT="$outcome"
	pair 0
	[ "$(uci -q get pangolin.main.enabled)" = 0 ]
	[ "$(cat "$TEST_AUTH_EVENTS")" = "$(printf 'sync\nstop-auth')" ]
	if [ "$outcome" = fail ]; then
		[ "$result" != 0 ]
		[ "$(jsonfilter -i /var/run/pangolin-auth/status.json -e '@.State')" = error ]
	else
		[ "$result" = 0 ]
	fi
done

# Service startup failure must keep the successful authentication intact.
TEST_AUTH_RESULT=success TEST_RESTART_FAIL=1
pair 0
check_started
echo 'Pangolin authentication auto-start, reauthentication, logout, cancellation and failure regressions passed.'
