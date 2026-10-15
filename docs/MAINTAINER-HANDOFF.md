# Maintainer handoff

This is the minimum context a future engineer or agent needs before modifying
or releasing the project. Last reviewed: 2026-10-14.

## Current baseline

| Item | Pin |
| --- | --- |
| OpenWrt stable | 25.12.5 |
| Target / package arch | `rockchip/armv8` / `aarch64_generic` |
| NanoPi profile | `friendlyarm_nanopi-r5c` |
| Package format | APK v3 |
| Pangolin CLI | 0.18.1, SHA-256 `568fcbf62a1c485d8cec617c635ae5769ff5d6729bcf412a7f0d13efb3d498ad` |
| Embedded Newt | 1.18.1, SHA-256 `e3e66632a3ca2eeb950cb74e087ca837e7eee98a9e0816fcc1e4528a355ccd18` |
| Embedded OLM | 1.10.1, SHA-256 `9de2a1b9daa21ce20b6642c2b948ab9616690800dbc0094835d2f711e3295f1a` |
| Go | 1.26.9 |
| Primary packages | `pangolin-cli-0.18.1-r1`, `luci-app-pangolin-1.0.0-r2` |
| Compatibility packages | `newt-1.18.1-r3`, `luci-app-newt-1.0.0-r4` |

At review time the official CLI release was 0.18.1. Standalone Newt's latest
release was 1.18.1 and its README said it was being phased out for the Pangolin
CLI. Recheck primary release pages before every release.

## Product decision

The primary app manages one official Pangolin site connector:

```text
pangolin up site --config-file /var/run/pangolin/site.json
```

It does not present a separate `pangolin up client` mode. The user clarified
that they want the current Pangolin site workflow kept close to upstream, with
LuCI for setup, service management, monitoring, and logs. Pangolin owns all
resource and access configuration.

The site uses Newt's userspace netstack by default and therefore has no host
NIC. Upstream `nativeMain` is exposed only as an advanced, off-by-default
option. When selected, `pangolin-network` registers the requested TUN as
`network.pangolin` and creates a firewall4 zone. Upstream Newt issue #403 still
reports native-main handshake failure; do not describe that path as generally
supported until upstream resolves it.

## Repository map

- `packages/pangolin-cli/`: CLI recipe, exact nested source archives, security
  patches, UCI, procd, site wrapper, optional network sync, credential sync,
  and headless configuration helper.
- `packages/luci-app-pangolin/`: LuCI form/status/log view, rpcd ucode API, ACL,
  and menu entry.
- `packages/newt/`, `packages/luci-app-newt/`: compatibility packages. Newt
  r3 adds credential-file hardening; LuCI r4 includes the RPC runtime fix.
- `examples/uci-defaults/90-pangolin`: setup when APKs are in the image.
- `examples/uci-defaults/99-pangolin-from-feed`: Firmware Selector late-network
  signed-feed bootstrap.
- `scripts/`: pinned SDK/ImageBuilder, signing, Docker, and artifact checks.
- `tests/`: static, network policy, APK/feed/ELF, target-ucode verification,
  and real rpcd/ubus execution in stock OpenWrt 25.12.5.
- `keys/openwrt-newt-public-key.pem`: stable public feed key.
- `private-key.pem`: ignored signing secret; never display or commit it.

## Runtime contract

`/etc/init.d/pangolin` owns exactly one named `site` procd instance. Keep that
name synchronized with `serviceInfo()` in `luci.pangolin`; a prior draft looked
for `main`, which falsely reported a running connector as stopped.

- UCI section: `pangolin.main`.
- Runtime JSON: `/var/run/pangolin/site.json`.
- Health file: `/var/run/pangolin/site-healthy`.
- Start-time file: `/var/run/pangolin/site-started`.
- Log tag: `pangolin`.
- Command wrapper: `/usr/libexec/pangolin-site-run`.

The wrapper sets a private runtime home and update opt-outs. The CLI is also
linked with `ManagedBy=openwrt`; APK is the only supported updater.

`pangolin-network sync` creates named netifd/firewall sections only when the
site, native-main, and local network management are all enabled. New zones
start input/output `ACCEPT`, forwarding `REJECT`; later syncs preserve an
administrator's zone policy. No forwarding or masquerading is created.

## RPC and the original “Operation failed” report

`luci-app-pangolin-1.0.0-r1` reliably failed `set_config` with ubus code 9.
The `boundedString()` validator used `\x00` inside a regular-expression
character class. OpenWrt ucode accepted bytecode compilation but raised
`Syntax error: Missing ']'` only when that function executed. Revision r2
checks CR/LF with a supported regex and NUL separately; legacy
`luci-app-newt` carries the same fix in r4. The code also hardens every
observed boundary:

- RPC declarations use `reject: true` and render transport exceptions.
- ucode `fs.popen()` receives command strings, not argv arrays (the latter can
  compile but fail at runtime on OpenWrt ucode).
- Empty JSON arrays remove absent UCI list options because ucode-mod-uci
  rejects an empty array as a value.
- Service actions use fixed allowlisted helpers and return captured output.
- Init validation writes the same actionable message to stderr and logd.
- The procd status lookup uses the actual `site` instance name.

Do not rely on `ucode -c` alone: it did not catch the lazy regex failure. Keep
the stock-OpenWrt RPC execution test in CI.

## Security boundaries

- UCI and runtime credentials must remain mode `0600`.
- Secret values never return from RPC; logs are re-redacted at the boundary.
- Newt's patch removes token/provisioning bodies from logs/errors and writes
  generated credentials as `0600`.
- OLM's patch changes its compiled-in API socket from `0666` to `0600`. The app
  does not manage client mode, but OLM is still embedded in the official CLI.
- Firmware images containing credentials are secrets even after first boot.
- Never expose, print, or commit `private-key.pem`.

Rebase and dry-run nested source patches on every upstream version update.

## Enrollment

The app accepts either an existing Site ID/secret or a one-time provisioning
key plus site name. Newt 1.18.1 has no anonymous approval-only enrollment. A
credential-bearing Firmware Selector image remains recoverable; recommend a
unique, short-lived provisioning key or post-deploy mode-0600 helper file.

## Build and test

```sh
./tests/check.sh
./tests/test_rpc_backends_openwrt.sh
./scripts/build-in-docker.sh
./scripts/verify-artifacts-in-docker.sh
./scripts/build-r5c-image-in-docker.sh
```

The RPC test downloads a checksum-pinned official 25.12.5 x86-64 rootfs and
executes both backends through real `rpcd`, `ubusd`, and ucode. The artifact
verifier must continue checking all four APKs, signed feed,
AArch64 ELF execution, exact dependency metadata and modes, embedded versions,
and both target-compiled ucode backends. The R5C image manifest must contain
`pangolin-cli` and `luci-app-pangolin`.

Container tests cannot prove real Pangolin enrollment, reverse-proxy traffic,
procd behavior on the board, or native-main viability. Complete the physical
acceptance list in `BUILDING.md` before calling a public release production
ready.

## Release procedure

1. Recheck official OpenWrt, CLI, Newt, and OLM releases and relevant issues.
2. Update versions, hashes, Go/toolchain pins, schemas, docs, and expectations
   as one coherent change.
3. Run all tests, then pass physical R5C acceptance.
4. Commit/push main and wait for green CI.
5. Tag only the verified commit using
   `v<pangolin-version>-openwrt<revision>`.
6. Download the release and independently verify its feed, signatures, hashes,
   and image manifest.

CI secret `OPENWRT_APK_PRIVATE_KEY_B64` is the stable feed key. Key rotation
requires an explicit migration for installed routers and all first-boot key
fingerprints.

## Primary upstream references

- Pangolin CLI: <https://github.com/fosrl/cli>
- Newt: <https://github.com/fosrl/newt>
- Install a site: <https://docs.pangolin.net/manage/sites/install-site>
- Configure a site: <https://docs.pangolin.net/manage/sites/configure-site>
- Install Newt: <https://docs.pangolin.net/manage/sites/install-newt>
- Newt native-main issue #403: <https://github.com/fosrl/newt/issues/403>
