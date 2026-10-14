#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
host_uid="$(id -u)"
host_gid="$(id -g)"

signing_args=()
if [ -f "$repo_root/private-key.pem" ]; then
	signing_args=(-e OPENWRT_APK_PRIVATE_KEY_FILE=/workspace/private-key.pem)
fi

docker run --rm \
	--platform linux/amd64 \
	-e OPENWRT_CACHE_DIR=/openwrt-cache \
	-e NEWT_USE_EXTERNAL_GO=1 \
	-e PANGOLIN_USE_EXTERNAL_GO=1 \
	-e HOST_UID="$host_uid" \
	-e HOST_GID="$host_gid" \
	"${signing_args[@]}" \
	-v openwrt-newt-sdk-cache:/openwrt-cache \
	-v "$repo_root:/workspace" \
	-w /workspace \
	golang:1.26.9-bookworm \
	bash -lc 'set -euo pipefail
export PATH=/usr/local/go/bin:$PATH
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends build-essential ca-certificates curl file gawk gettext libncurses-dev python3 rsync unzip wget zstd
./scripts/build-openwrt.sh
chown -R "$HOST_UID:$HOST_GID" /workspace/dist'
