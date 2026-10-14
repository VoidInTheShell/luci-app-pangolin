# Architecture

## Goals

The integration should feel like a native OpenWrt network service while
leaving all remote routing and reverse-proxy policy in Pangolin. It must be
installable as a normal OpenWrt 25.12 APK, survive upgrades, avoid exposing
credentials through process arguments or LuCI RPC, and remain reproducible from
the tagged upstream source.

## Component model

```text
LuCI browser
    │ authenticated ubus RPC
    ▼
luci.newt rpcd plugin ───────► /etc/config/newt (0600)
    │ status/actions/logs                  │
    ▼                                      │ service start
OpenWrt ubus + logd                         ▼
                                      /etc/init.d/newt
                                             │ renders root-only JSON
                                             ▼
                                 /var/run/newt/config.json (0600)
                                             │
                                             ▼
                                      procd → newt
                                             │ outbound HTTPS/WSS/UDP
                                             ▼
                                      Pangolin control plane
```

`luci-app-newt` depends on `newt`, so one feed install resolves both packages.
The LuCI files are `noarch`; the Newt package is `aarch64_generic` on the R5C.

## Service lifecycle

`/etc/init.d/newt` is an `rc.common` service using `USE_PROCD=1`. It validates
that an endpoint and an authentication method are present, converts UCI into
Newt's JSON schema with `jshn`, and starts a single `main` instance. Standard
output and error go to `logd`. The default respawn policy waits five seconds and
stops a rapid crash loop after five retries inside the stability window.

The fixed health file `/var/run/newt/healthy` is managed by Newt itself. Newt
creates it after successfully establishing the tunnel and removes it after
connection loss. LuCI therefore distinguishes:

- disabled;
- stopped;
- running but starting/reconnecting; and
- connected.

## Credential lifecycle

Persistent secrets live only in `/etc/config/newt`, mode `0600`. The rpcd
backend returns boolean `has_*` fields instead of credential values. A blank
password field means “keep the stored value”; clearing one requires an explicit
checkbox.

Newt 1.18.1's upstream debug logging prints token and provisioning response
bodies. The package applies a narrow source patch which retains status-level
diagnostics without writing those credentials to `logd`. The RPC backend also
redacts stored secrets as a second boundary before returning log text to LuCI.

The service renders `/var/run/newt/config.json` with a restrictive umask and
passes only its path to Newt. Secrets do not appear in `ps` output or the procd
command array.

For one-time provisioning, Newt exchanges the key for an ID and secret and
writes them into the runtime JSON. A second supervised helper observes that
file, stores the permanent credentials in UCI, removes the one-time key, and
switches the authentication mode to normal credentials. No credential is
passed through a shell command argument.

## LuCI and RPC boundary

The browser does not receive raw UCI access. Its ACL grants only these methods:

- read: `get_config`, `get_status`, `get_logs`;
- write: `set_config`, `service_action`.

The rpcd plugin allowlists every accepted setting and validates URLs, paths,
durations, integer bounds, lists, booleans, and service actions. Log output is
redacted again at the server boundary even though Newt is not expected to log
credentials.

## Updates

Newt 1.18.1 contains an in-place self-updater. The `procd` environment uses
Newt's supported self-update opt-out so that `/usr/bin/newt` cannot drift away
from the installed APK. Releases are upgraded through the OpenWrt package feed.

## Native versus userspace networking

The default uses Newt's userspace WireGuard/netstack implementation and does
not require Docker or a kernel tunnel device. Advanced native-interface flags
are exposed for completeness, but require compatible kernel WireGuard support
and should remain disabled on a standard R5C installation unless specifically
needed.

## Packaging and releases

OpenWrt 25.12 uses APK v3 repositories. A public release consists of:

- the architecture-specific Newt APK;
- the `noarch` LuCI APK;
- a signed `packages.adb` index; and
- a stable P-256 public key installed under `/etc/apk/keys/`.

The package feed must be rebuilt for each OpenWrt release line and package
architecture. A single ARM64 Newt binary is not named after the R5C because
`aarch64_generic` also correctly serves other baseline ARMv8 OpenWrt boards.

## Deliberate non-goals

- Managing Pangolin resources or users from LuCI.
- Replacing Pangolin's control plane.
- Docker-based execution.
- Firmware flashing or kernel modification.
- Automatic in-place replacement of the package-managed Newt binary.
