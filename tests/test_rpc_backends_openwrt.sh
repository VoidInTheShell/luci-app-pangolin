#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
openwrt_version="${OPENWRT_VERSION:-25.12.5}"
rootfs_name="openwrt-${openwrt_version}-x86-64-rootfs.tar.gz"
rootfs_sha256='2dae4250b1b742062ed5787adcdc9dd6d26c7f69f94ced46548eb512d5957e8a'
rootfs_url="https://downloads.openwrt.org/releases/${openwrt_version}/targets/x86/64/${rootfs_name}"
cache_dir="${OPENWRT_CACHE_DIR:-${repo_root}/.cache}"
rootfs_path="${cache_dir}/${rootfs_name}"
image_tag="openwrt-newt-rpc-test:${openwrt_version}-${rootfs_sha256:0:12}"
container_name="openwrt-newt-rpc-test-$$-${RANDOM}"

for command in curl docker jq seq sha256sum; do
	command -v "$command" >/dev/null 2>&1 || {
		echo "Required command not found: $command" >&2
		exit 1
	}
done

mkdir -p "$cache_dir"
if [ ! -f "$rootfs_path" ]; then
	curl -fL --retry 3 -o "$rootfs_path" "$rootfs_url"
fi
echo "${rootfs_sha256}  ${rootfs_path}" | sha256sum -c - >/dev/null

if ! docker image inspect "$image_tag" >/dev/null 2>&1; then
	docker import --platform linux/amd64 "$rootfs_path" "$image_tag" >/dev/null
fi

cleanup() {
	docker rm -f "$container_name" >/dev/null 2>&1 || true
}
trap cleanup EXIT

docker run -d --name "$container_name" --privileged --platform linux/amd64 \
	"$image_tag" /sbin/init >/dev/null 2>&1

ready='0'
for _attempt in $(seq 1 60); do
	if docker exec "$container_name" ubus call system board '{}' >/dev/null 2>&1; then
		ready='1'
		break
	fi
	sleep 1
done
[ "$ready" = '1' ] || {
	echo 'The disposable OpenWrt rpcd test container did not become ready.' >&2
	exit 1
}

docker exec "$container_name" mkdir -p /usr/share/rpcd/ucode /usr/libexec

copy_file() {
	local source="$1"
	local destination="$2"
	docker cp "$repo_root/$source" "$container_name:$destination"
}

copy_file packages/luci-app-pangolin/root/usr/share/rpcd/ucode/luci.pangolin \
	/usr/share/rpcd/ucode/luci.pangolin
copy_file packages/pangolin-cli/files/pangolin.config /etc/config/pangolin
copy_file packages/pangolin-cli/files/pangolin.init /etc/init.d/pangolin
copy_file packages/pangolin-cli/files/pangolin-network /usr/libexec/pangolin-network
copy_file packages/pangolin-cli/files/pangolin-service-action /usr/libexec/pangolin-service-action
copy_file packages/pangolin-cli/files/pangolin-site-run /usr/libexec/pangolin-site-run

copy_file packages/luci-app-newt/root/usr/share/rpcd/ucode/luci.newt \
	/usr/share/rpcd/ucode/luci.newt
copy_file packages/newt/files/newt.config /etc/config/newt
copy_file packages/newt/files/newt.init /etc/init.d/newt
copy_file packages/newt/files/newt-run /usr/libexec/newt-run
copy_file packages/newt/files/newt-service-action /usr/libexec/newt-service-action

docker exec "$container_name" chmod 0600 /etc/config/pangolin /etc/config/newt
docker exec "$container_name" chmod 0755 \
	/usr/share/rpcd/ucode/luci.pangolin \
	/usr/share/rpcd/ucode/luci.newt \
	/etc/init.d/pangolin \
	/etc/init.d/newt \
	/usr/libexec/pangolin-network \
	/usr/libexec/pangolin-service-action \
	/usr/libexec/pangolin-site-run \
	/usr/libexec/newt-run \
	/usr/libexec/newt-service-action
docker exec "$container_name" /etc/init.d/rpcd restart >/dev/null 2>&1

objects_ready='0'
for _attempt in $(seq 1 20); do
	if docker exec "$container_name" ubus list luci.pangolin >/dev/null 2>&1 && \
	   docker exec "$container_name" ubus list luci.newt >/dev/null 2>&1; then
		objects_ready='1'
		break
	fi
	sleep 1
done
[ "$objects_ready" = '1' ] || {
	echo 'The LuCI test RPC objects were not registered.' >&2
	exit 1
}

assert_rpc_success() {
	local object="$1"
	local method="$2"
	local payload="$3"
	local result
	result="$(docker exec "$container_name" ubus call "$object" "$method" "$payload")"
	jq -e '.success == true' <<< "$result" >/dev/null
}

assert_rpc_success luci.pangolin set_config \
	'{"config":{"endpoint":"https://app.pangolin.net","auth_mode":"credentials","id":"rpc-test-site","secret":"rpc-test-secret","enabled":"1","local_endpoint_interfaces":[],"tls_client_ca":[]}}'
assert_rpc_success luci.newt set_config \
	'{"config":{"endpoint":"https://app.pangolin.net","auth_mode":"credentials","id":"rpc-test-site","secret":"rpc-test-secret","enabled":"1","local_endpoint_interfaces":[],"tls_client_ca":[]}}'

for config in pangolin newt; do
	[ "$(docker exec "$container_name" uci -q get "$config.main.id")" = 'rpc-test-site' ]
	[ "$(docker exec "$container_name" uci -q get "$config.main.secret")" = 'rpc-test-secret' ]
	if docker exec "$container_name" uci -q get "$config.main.local_endpoint_interfaces" >/dev/null; then
		echo "$config stored an empty array as a UCI list." >&2
		exit 1
	fi
done

pangolin_config="$(docker exec "$container_name" ubus call luci.pangolin get_config '{}')"
newt_config="$(docker exec "$container_name" ubus call luci.newt get_config '{}')"
jq -e '.has_secret == true and (has("secret") | not)' <<< "$pangolin_config" >/dev/null
jq -e '.has_secret == true and (has("secret") | not)' <<< "$newt_config" >/dev/null

invalid_result="$(docker exec "$container_name" ubus call luci.pangolin set_config \
	'{"config":{"endpoint":"http://insecure.example.com"}}')"
jq -e '.success == false and (.error | contains("HTTPS"))' <<< "$invalid_result" >/dev/null

assert_rpc_success luci.pangolin set_config \
	'{"config":{"clear_secret":"1","enabled":"0"}}'
assert_rpc_success luci.newt set_config \
	'{"config":{"clear_secret":"1","enabled":"0"}}'
for config in pangolin newt; do
	if docker exec "$container_name" uci -q get "$config.main.secret" >/dev/null; then
		echo "$config did not clear its stored secret." >&2
		exit 1
	fi
done

docker exec "$container_name" ubus call luci.pangolin get_status '{}' >/dev/null
docker exec "$container_name" ubus call luci.pangolin get_logs '{"lines":20}' >/dev/null
docker exec "$container_name" ubus call luci.newt get_status '{}' >/dev/null
docker exec "$container_name" ubus call luci.newt get_logs '{"lines":20}' >/dev/null

echo "Both RPC backends passed in stock OpenWrt ${openwrt_version} rpcd/ubus."
