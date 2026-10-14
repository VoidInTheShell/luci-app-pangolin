# Architecture and security model

## Scope

The primary package follows Pangolin's current Linux site installation model
as closely as OpenWrt permits:

```text
pangolin up site --config-file /var/run/pangolin/site.json
```

OpenWrt is Linux, but it uses `procd`, UCI, ubus/rpcd, netifd, and firewall4
instead of systemd. The package supplies only that platform integration. It
does not reimplement Pangolin's control plane or run Docker.

```text
LuCI browser
    │ authenticated ubus JSON-RPC
    ▼
luci.pangolin rpcd plugin ───────► /etc/config/pangolin (0600)
    │ status, actions, logs                      │
    │                                            ▼
    │                                  /etc/init.d/pangolin
    │                                            │ procd instance: site
    │                                            ▼
    │                              /var/run/pangolin/site.json
    │                                            │
    │                                            ▼
    │                                  pangolin up site
    │                                      (Newt 1.18.1)
    │                                            │
    └────────► netifd/firewall4 ◄──── optional native-main TUN
```

Pangolin remains authoritative for sites, resources, targets, clients, and
access policies. LuCI manages this router's connector only.

## Userspace networking and the optional NIC

The standard Newt site connector uses a userspace netstack. Reverse-proxy
traffic is terminated and forwarded inside the process, so no Linux NIC,
kernel route, netifd interface, or firewall zone appears. This is normal and is
the recommended mode.

Upstream also exposes `nativeMain`. If enabled, Newt requests `/dev/net/tun`
and creates a host interface. The optional OpenWrt integration binds that name
to `network.pangolin` and zone `firewall.pangolin` so counters and policy are
visible in LuCI. The initial input policy is `ACCEPT` because site proxy
listeners bind on the tunnel address; forwarding remains `REJECT` and no LAN
forwarding is created.

This path is labeled experimental because upstream Newt issue #403 reports a
native-main handshake failure. The package does not imply that enabling a TUN
is necessary for normal site/reverse-proxy operation.

The separate Pangolin machine-client role is intentionally outside this LuCI
app's scope. This avoids conflating a site connector with a client VPN and
keeps upgrades close to the official `pangolin up site` contract.

## Service lifecycle

`/etc/init.d/pangolin` uses `USE_PROCD=1` and one named `site` instance. It:

- validates endpoint and credentials before launch;
- renders Newt's JSON configuration with umask `077`;
- optionally synchronizes native-main network configuration;
- sends stdout/stderr to logd;
- watches `/etc/config/pangolin` and supports reload;
- applies a bounded respawn policy; and
- removes transient runtime state on stop.

A wrapper records start time, sets a private runtime home, disables component
self-update behavior, and executes the official CLI. The binary is linked with
`ManagedBy=openwrt`; APK remains the sole owner of `/usr/bin/pangolin`.

Provisioning initially writes generated credentials into the root-only runtime
JSON. A small ucode helper copies them back to UCI, switches to credentials
mode, and removes the one-time key.

## LuCI JSON-RPC boundary

The browser never invokes shell commands. It calls an rpcd ucode object with
these ACLs:

- read: `get_config`, `get_status`, `get_logs`;
- write: `set_config`, `service_action`, `sync_network`.

The backend allowlists every field, validates types/ranges/paths/URLs, never
returns stored secrets, and sends service actions through fixed allowlisted
helpers. RPC transport errors reject the browser promise so the UI renders the
actual ubus error. Init validation errors are captured and also sent to logd,
addressing the previous generic **Operation failed** behavior.

## Credential and local security

- `/etc/config/pangolin` and runtime JSON are mode `0600`.
- Runtime directories use umask `077`.
- Secrets remain out of process arguments and RPC responses.
- Embedded Newt is patched not to log token/provisioning response bodies and
  to retain mode `0600` when writing generated credentials.
- Embedded OLM is patched to use a root-only control socket even though this
  app does not manage client mode; the official CLI still contains that code.
- The RPC log method redacts every stored secret again before returning text.
- First-boot images containing credentials remain sensitive after writable
  bootstrap files are deleted.

## Packaging

The R5C target is `rockchip/armv8` with package architecture
`aarch64_generic`. `pangolin-cli` is architecture-specific;
`luci-app-pangolin` is `noarch` and depends on it. One `apk add
luci-app-pangolin` installs the complete app.

Sources are version- and checksum-pinned. The CLI build replaces its Newt and
OLM modules with exact local source archives before applying narrow security
patches. Releases contain signed APK v3 packages and a signed `packages.adb`
feed.

## Deliberate non-goals

- Managing Pangolin resources or access policies in LuCI.
- Running systemd or Docker on the router.
- Treating a machine client as part of site configuration.
- Credential-free approval enrollment not exposed by upstream.
- Automatically forwarding Pangolin traffic to LAN.
- Allowing an embedded component to self-update outside APK.
