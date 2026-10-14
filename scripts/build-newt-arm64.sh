#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
host_uid="$(id -u)"
host_gid="$(id -g)"

docker run --rm \
	--platform linux/amd64 \
	-e HOST_UID="$host_uid" \
	-e HOST_GID="$host_gid" \
	-v "$repo_root:/workspace" \
	-w /tmp \
	golang:1.26.9 \
	bash -lc 'set -euo pipefail
export PATH=/usr/local/go/bin:$PATH
version=1.18.1
source_hash=e3e66632a3ca2eeb950cb74e087ca837e7eee98a9e0816fcc1e4528a355ccd18
wget -qO newt.tar.gz "https://codeload.github.com/fosrl/newt/tar.gz/refs/tags/${version}"
echo "${source_hash}  newt.tar.gz" | sha256sum -c -
tar -xzf newt.tar.gz
cd "newt-${version}"
patch -p1 < /workspace/packages/newt/patches/010-redact-sensitive-debug-logging.patch
mkdir -p /workspace/dist/raw
CGO_ENABLED=0 GOOS=linux GOARCH=arm64 GOARM64=v8.0 \
	go build -trimpath -buildvcs=false \
	-ldflags "-s -w -X main.newtVersion=${version} -X main.newtPlatform=linux_arm64" \
	-o /workspace/dist/raw/newt_linux_arm64 ./
chown "$HOST_UID:$HOST_GID" /workspace/dist/raw/newt_linux_arm64
sha256sum /workspace/dist/raw/newt_linux_arm64'

file "$repo_root/dist/raw/newt_linux_arm64"
