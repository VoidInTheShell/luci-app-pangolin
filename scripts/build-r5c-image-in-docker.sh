#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
host_uid="$(id -u)"
host_gid="$(id -g)"

docker run --rm \
	--platform linux/amd64 \
	-e OPENWRT_CACHE_DIR=/openwrt-cache \
	-e HOST_UID="$host_uid" \
	-e HOST_GID="$host_gid" \
	-v openwrt-newt-sdk-cache:/openwrt-cache \
	-v "$repo_root:/workspace" \
	-w /workspace \
	debian:bookworm-slim \
	bash -lc 'set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends build-essential ca-certificates curl file gawk gettext libncurses-dev python3 python3-distutils rsync unzip wget zstd
./scripts/build-r5c-image.sh
chown -R "$HOST_UID:$HOST_GID" /workspace/dist'
