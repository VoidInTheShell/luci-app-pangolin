# Installation and troubleshooting

These packages target stock OpenWrt 25.12.5 on the FriendlyElec NanoPi R5C.
The APKs may work on other `aarch64_generic` devices, but the prebuilt firmware
images are R5C-specific.

## Preflight

SSH to the router and verify the release, target, and package architecture:

```sh
ubus call system board
apk --print-arch
```

Expected values include OpenWrt `25.12.5`, `rockchip/armv8`, and
`aarch64_generic`. OpenWrt 25.12 uses APK v3; do not use `opkg` or packages for
a different OpenWrt release or CPU.

## Add the signed feed and install through LuCI

LuCI cannot safely introduce a new third-party repository trust key by itself.
Establish the trust anchor once over SSH:

```sh
wget -O /tmp/openwrt-newt-public-key.pem \
  https://github.com/alexanderjlynn/openwrt-newt/releases/latest/download/openwrt-newt-public-key.pem
echo '54a584f2a271bddb263225be0ed7e972fd506529adcc03993a8e50bac32c7546  /tmp/openwrt-newt-public-key.pem' \
  | sha256sum -c -
cp /tmp/openwrt-newt-public-key.pem \
  /etc/apk/keys/openwrt-newt-public-key.pem
chmod 0644 /etc/apk/keys/openwrt-newt-public-key.pem
rm -f /tmp/openwrt-newt-public-key.pem

echo 'https://github.com/alexanderjlynn/openwrt-newt/releases/latest/download/packages.adb' \
  > /etc/apk/repositories.d/openwrt-newt.list
apk update
```

Then:

1. Open **System → Software** and refresh package lists.
2. Search for `luci-app-pangolin` and install it.
3. Hard-refresh LuCI or sign in again.
4. Open **Services → Pangolin**.

The equivalent SSH command is `apk add luci-app-pangolin`. It installs the
matching AArch64 `pangolin-cli`, `kmod-tun`, and runtime dependencies. Do not
use `--allow-untrusted` with this signed feed.

## Manual package upload in LuCI

Download these release assets on a trusted computer:

- `pangolin-cli-0.18.1-r2.apk`
- `luci-app-pangolin-1.0.0-r3.apk`
- `packages-sha256sums`
- `openwrt-newt-public-key.pem`

Verify the published key fingerprint above and both package hashes. Install
the public key in `/etc/apk/keys/` first. In **System → Software → Upload
Package**, upload `pangolin-cli` first and `luci-app-pangolin` second. Keep the
official OpenWrt repositories enabled so APK can resolve kernel and LuCI
dependencies.

If the UI cannot solve the two local files as one transaction, copy them to
`/tmp` and run:

```sh
apk add /tmp/pangolin-cli-0.18.1-r2.apk \
  /tmp/luci-app-pangolin-1.0.0-r3.apk
```

## Install the promoted native-main release

The tested `v0.18.1-openwrt3-rc1` build has been promoted to stable/latest.
Its original tag is retained to preserve download links. The standard stable
feed now installs these same packages. Existing users can run `apk update`
and `apk add --upgrade pangolin-cli luci-app-pangolin`.

The original pinned repository also remains available over SSH:

```sh
test -s /etc/apk/keys/openwrt-newt-public-key.pem || {
  echo "OpenWrt Newt signing key is missing"
  exit 1
}

echo 'https://github.com/alexanderjlynn/openwrt-newt/releases/download/v0.18.1-openwrt3-rc1/packages.adb' \
  > /etc/apk/repositories.d/openwrt-newt-rc.list

apk update
apk add --upgrade pangolin-cli luci-app-pangolin

/etc/init.d/rpcd restart
/etc/init.d/pangolin restart
```

Verify:

```sh
apk list -I | grep -E '^(pangolin-cli|luci-app-pangolin)-'
```

Expected:

```text
pangolin-cli-0.18.1-r2
luci-app-pangolin-1.0.0-r3
```

When the stable feed is configured, remove the temporary
`/etc/apk/repositories.d/openwrt-newt-rc.list` and run `apk update`.
This does not downgrade installed packages.

For a LuCI-only package upload, download those same two APKs on a trusted
computer, open **System → Software → Upload Package**, and install
`pangolin-cli` first and `luci-app-pangolin` second. The public signing key and
official OpenWrt repositories must already be configured.

To enable the native-TUN feature:

1. Open **Services → Pangolin → Network**.
2. Set **Main tunnel networking** to **Native Linux TUN (experimental)**.
3. Leave **Native main interface name** as `pangolin`.
4. Enable **Register native interface with OpenWrt**.
5. Save and apply, then verify `pangolin` under **Network → Interfaces**.

The interface device appears only after Newt successfully establishes the
native tunnel. Use `logread -e pangolin` if the registered netifd interface is
present but its Linux device is not. Complete checks and exact rollback steps
are in [Native-main prerelease testing](NATIVE-MAIN-TESTING.md).

## Configure the site

In Pangolin, create or select a site and copy its ID and secret. In
**Services → Pangolin**:

1. Set **Pangolin endpoint** to the public HTTPS URL, such as
   `https://pangolin.example.com`. Add `:8443` only if that is the public
   Pangolin HTTPS port.
2. Select **Existing Site ID and secret**, paste both values, and enable the
   site connector.
3. Save. The page should progress from **Starting / reconnecting** to
   **Connected**, and log messages should appear on the same page.

The alternative **One-time provisioning key** mode requires a provisioning key
and a unique site name. After Newt receives permanent credentials, the package
persists them to root-only UCI and clears the one-time key. Newt 1.18.1 does
not expose a credential-free “join and wait for administrator approval” flow.

Pangolin continues to manage resources, targets, access rules, and clients.
The LuCI app intentionally manages only the local connector.

## Verify operation

```sh
/etc/init.d/pangolin enabled
ubus call service list '{"name":"pangolin"}'
logread -e pangolin
ls -l /etc/config/pangolin /var/run/pangolin/site.json
```

The service instance is named `site`. `procd` restarts it after failures, and
stdout/stderr go to OpenWrt logd.

## Optional native-main interface

Normal site mode uses Newt's userspace netstack and creates no host NIC. That
is the upstream default and the recommended reverse-proxy configuration.

The advanced **Native main tunnel (experimental)** setting asks Newt to create
a Linux TUN. When **Register native interface with OpenWrt** is also enabled,
the package creates:

- Linux device and netifd network named `pangolin` by default;
- **Network → Interfaces → pangolin**; and
- firewall4 zone `pangolin` with initial input/output `ACCEPT` and forwarding
  `REJECT`.

Input is initially accepted because the site proxy listeners bind to the
tunnel address. Review that policy for the router services in scope. Existing
administrator changes to the named zone are preserved on later syncs.

**Unmanaged** is the correct LuCI protocol: `proto=none` lets Pangolin manage
the TUN and its addresses. No MAC address is expected because a TUN transports
IP packets rather than Ethernet frames. Do not change it to DHCP/static or
assign a MAC simply to change those displays.

This is not the default because upstream issue #403 reports a `native-main`
handshake failure. Treat it as experimental until upstream closes that gap.
Check it with:

```sh
ip link show pangolin
uci show network.pangolin
uci show firewall.pangolin
```

## Diagnosing save or start failures

The RPC backend returns validation and service output to LuCI instead of only
showing **Operation failed**. After an upgrade, restart rpcd and hard-refresh
the browser if an old cached view remains:

```sh
apk -U add pangolin-cli luci-app-pangolin
/etc/init.d/rpcd restart
/etc/init.d/pangolin restart
logread -e pangolin
ubus -v list luci.pangolin
```

`luci-app-pangolin-1.0.0-r1` had a ucode validation bug that made every save
fail with `luci.pangolin/set_config` ubus code 9. Upgrade to `1.0.0-r2` or
newer, restart rpcd, and reload LuCI. The matching `pangolin-cli` remains
`0.18.1-r1`; it was not the source of this save failure. Confirm the installed
revision with:

```sh
apk list -I luci-app-pangolin pangolin-cli
```

Common causes are an endpoint without `https://`, a missing half of the
ID/secret pair, an invalid path or interface name, or enabling native-main
without `/dev/net/tun`. For the legacy app, install `newt-1.18.1-r3` and
`luci-app-newt-1.0.0-r4` together; those revisions include the same actionable
RPC error handling.

## Recover missing client integration ownership

In **client** mode, `network.pangolin_client`, `firewall.pangolin_client`,
`firewall.pangolin_client_lan`, and the optional Nikki bypass section are
tracked in `/etc/pangolin/integration-backup.json`. Keep this root-only file
with any backup of the generated UCI sections. Regular synchronization never
takes over pre-existing, unowned sections.

If the log reports `Refusing to replace existing network.pangolin_client`
(or a corresponding firewall/Nikki section), first inspect the named sections
and save a root-only backup of `/etc/config/network`, `/etc/config/firewall`,
`/etc/config/nikki` if present, and `/etc/pangolin`. With the client running
and no pending UCI edits, an administrator can explicitly recover ownership:

```sh
/usr/libexec/pangolin-client-integration recover
/usr/libexec/pangolin-client-integration sync
```

Recovery adopts existing sections **only when their type, every option, and
scalar/list types exactly match the currently requested client configuration**.
It validates all candidates before adoption; extra options or changed policies
are refused, not overwritten. A malformed ownership file is also refused. Do
not delete that file or remove administrator policy to bypass the protection.
After successful recovery, normal stop/rollback removes only unchanged owned
sections. Ownership saves use a same-filesystem temporary file and atomic rename.

The watcher logs the specific integration error once when it changes, keeps
retrying every five seconds, and logs recovery after a later successful sync.
Repeated identical errors no longer flood logd. A running `integration`
instance alone does **not** mean the `client` instance is alive: check both
instances and the client registration status. If `procd` has exhausted the
configured restart limit after a network outage, restore connectivity first,
then use `/etc/init.d/pangolin start` and check registration again.

## Migrate from the legacy Newt app

1. Obtain the endpoint, site ID, and secret from a secure source; LuCI never
   reveals stored secrets.
2. Install and configure `luci-app-pangolin`, but leave it disabled.
3. Disable **Services → Pangolin Newt**.
4. Enable **Services → Pangolin** and verify a connected site.
5. Remove the legacy pair only after confirming real proxy traffic.

Never run two connectors with the same site credentials.

## Update or remove

Update only the user-installed packages rather than indiscriminately upgrading
the OpenWrt base system:

```sh
apk update
apk add --upgrade pangolin-cli luci-app-pangolin
/etc/init.d/rpcd restart
```

Before removal, save the root-only UCI file if needed:

```sh
/etc/init.d/pangolin stop
cp -p /etc/config/pangolin /root/pangolin.config.backup
apk del luci-app-pangolin pangolin-cli
```

Named network/firewall sections are not silently deleted because an
administrator may have attached policy to them. Remove them manually only
after confirming they are unused.
