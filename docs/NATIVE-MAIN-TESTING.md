# Native-main setup and validation

The tested `v0.18.1-openwrt3-rc1` release was promoted in place to stable/latest
after the user confirmed operation on a NanoPi R5C. The original tag is retained
to preserve existing asset URLs. Native-main remains an opt-in upstream feature.

## Scope and expected benefit

Pangolin's normal site connector runs its WireGuard tunnel in Newt's gVisor
userspace netstack. That mode is the known-good reverse-proxy path, but it does
not create a Linux network device and therefore cannot appear in OpenWrt's
Network or Firewall pages.

Newt's `nativeMain` mode instead creates a Linux TUN. The OpenWrt package binds
that daemon-owned device to an unmanaged netifd network and a firewall4 zone,
matching the integration pattern commonly used for Tailscale and ZeroTier.
The practical benefits are:

- per-interface RX/TX counters and operational state in LuCI;
- firewall zones and rules for traffic entering the router over Pangolin;
- kernel routes, policy-based routing, and monitoring integrations; and
- a kernel-visible path for subnet and exit-node traffic.

It is not expected to transform ordinary reverse-proxy throughput. Newt still
accepts and proxies those connections in the Go process. Routed traffic may
benefit from avoiding parts of the userspace network stack, but measure it on
the target workload rather than assuming a gain.

Upstream Newt issue
[#403](https://github.com/fosrl/newt/issues/403) still reports a native-main
handshake failure. The upstream maintainer describes native modes as
experimental. Native-main therefore remains opt-in even though this package
release has been promoted after on-device confirmation.

## Versions

The candidate uses the newest independent upstream releases available at build
time:

- Pangolin server: 1.24.0;
- Pangolin CLI: 0.18.1;
- embedded Newt: 1.18.1; and
- OpenWrt: 25.12.5.

Pangolin server, CLI, and Newt version numbers do not move in lockstep. The
LuCI status panel reports the CLI and embedded Newt versions separately.

## Install the promoted release

The stable `latest` feed now provides this build. With the signing key and
stable feed configured as described in [Installation](INSTALLING.md), run:

```sh
apk update
apk add --upgrade pangolin-cli luci-app-pangolin
/etc/init.d/rpcd restart
/etc/init.d/pangolin restart
```

Alternatively, download its two exact packages over SSH:

```sh
cd /tmp
wget https://github.com/alexanderjlynn/openwrt-newt/releases/download/v0.18.1-openwrt3-rc1/pangolin-cli-0.18.1-r2.apk
wget https://github.com/alexanderjlynn/openwrt-newt/releases/download/v0.18.1-openwrt3-rc1/luci-app-pangolin-1.0.0-r3.apk
apk add --upgrade \
  /tmp/pangolin-cli-0.18.1-r2.apk \
  /tmp/luci-app-pangolin-1.0.0-r3.apk
/etc/init.d/rpcd restart
```

The public signing key from the stable installation remains valid. Existing
credentials and the userspace default are preserved during the upgrade.

## Enable the interface

1. Open **Services → Pangolin → Network**.
2. Set **Main tunnel networking** to **Native Linux TUN (experimental)**.
3. Leave **Native main interface name** as `pangolin`.
4. Enable **Register native interface with OpenWrt**.
5. Save and apply.

The package creates `network.pangolin` with protocol `none` and binds it to the
daemon-owned `pangolin` device. It also creates a `pangolin` firewall zone with
initial input/output `ACCEPT` and forwarding `REJECT`. No forwarding to LAN or
WAN and no masquerading are added automatically.

LuCI's **Unmanaged** protocol and absent MAC address are expected: netifd uses
`proto=none` because Pangolin owns the device configuration, and this Layer 3
TUN has no Ethernet header or MAC address. Do not add DHCP/static configuration
or an artificial MAC to change the display.

The status panel should show all of the following:

- service **Connected**;
- main tunnel networking **Native Linux TUN**;
- Linux device `pangolin` present;
- OpenWrt network and firewall both registered; and
- increasing RX/TX counters while traffic flows.

Also verify over SSH:

```sh
ip -details link show dev pangolin
ip address show dev pangolin
uci show network.pangolin
uci show firewall.pangolin
ubus call network.interface.pangolin status
logread -e pangolin
```

Confirm existing reverse-proxy resources still work before adding any
forwarding. Then create only the firewall forwarding and routes required by the
specific site-to-site or zero-trust use case.

## Disable native mode or roll back

The fastest recovery does not require a package downgrade: change **Main
tunnel networking** back to **Userspace netstack**, save, and confirm the site
reconnects. The named netifd and firewall sections are preserved so the package
does not destroy administrator policy; delete them manually only if no longer
needed.

To restore the exact known-good package revisions:

```sh
cd /tmp
wget https://github.com/alexanderjlynn/openwrt-newt/releases/download/v0.18.1-openwrt2/pangolin-cli-0.18.1-r1.apk
wget https://github.com/alexanderjlynn/openwrt-newt/releases/download/v0.18.1-openwrt2/luci-app-pangolin-1.0.0-r2.apk
apk add \
  /tmp/pangolin-cli-0.18.1-r1.apk \
  /tmp/luci-app-pangolin-1.0.0-r2.apk
/etc/init.d/rpcd restart
/etc/init.d/pangolin restart
```

Passing the exact local APK paths constrains the transaction to those stable
revisions; APK v3 has no `--allow-downgrade` option.

The stable feed and `releases/latest` now point to the promoted
`v0.18.1-openwrt3-rc1`. The earlier `v0.18.1-openwrt2` remains available for rollback.
