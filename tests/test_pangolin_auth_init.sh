#!/bin/sh
# Installation/boot must not begin pairing; explicit requests must reach config.
set -eu
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
. "$repo_root/packages/pangolin-cli/files/pangolin-auth.init"
config_load() { touch "$work/config-loaded"; }
config_get() { endpoint=http://invalid.example.test; }
start_service
[ ! -e "$work/config-loaded" ]
if start_service pair >/dev/null 2>&1; then
	echo 'Explicit pairing must validate the HTTPS endpoint.' >&2
	exit 1
fi
[ -e "$work/config-loaded" ]
echo 'Auth init ignores installation/boot starts and accepts explicit pairing requests.'
