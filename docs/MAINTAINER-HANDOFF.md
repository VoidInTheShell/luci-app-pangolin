# Maintainer handoff

This is the operational context needed to continue the project without
re-discovering its packaging, security, and release decisions. It was last
reviewed on 2026-10-13.

## Current baseline

| Item | Pin |
| --- | --- |
| OpenWrt stable | 25.12.5 |
| OpenWrt target | `rockchip/armv8` |
| Package architecture | `aarch64_generic` |
| NanoPi profile | `friendlyarm_nanopi-r5c` |
| Package format | APK v3 |
| Newt | 1.18.1 |
| Newt source SHA-256 | `e3e66632a3ca2eeb950cb74e087ca837e7eee98a9e0816fcc1e4528a355ccd18` |
| Go toolchain | 1.26.9 |
| Package revisions | `newt-1.18.1-r2`, `luci-app-newt-1.0.0-r2` |

Newt 1.18.1 was still the latest upstream release at the review date. Go
1.27 exists, but Newt declares Go 1.26 and the pinned OpenWrt 25.12 package
feed supplies `golang1.26/host`; the external Docker build therefore uses the
latest compatible 1.26 patch rather than silently changing toolchain families.

## Repository map

- `packages/newt/`: Go package recipe, UCI defaults, `procd` service, runtime
  config renderer, provisioning credential sync, and secure CLI helper.
- `packages/luci-app-newt/`: LuCI JavaScript view, ucode `rpcd` object, menu,
  and least-privilege ACL.
- `examples/uci-defaults/90-newt`: ImageBuilder configuration when APKs are
  already embedded.
- `examples/uci-defaults/99-newt-from-feed`: public Firmware Selector script;
  creates a temporary late-boot service because early `uci-defaults` has no
  reliable network.
- `scripts/`: pinned SDK, ImageBuilder, Docker, signing, and verification
  entry points.
- `tests/`: static checks plus APK/feed/ELF/payload verification.
- `keys/openwrt-newt-public-key.pem`: stable public repository key.
- `private-key.pem`: ignored local signing key. It must never be committed,
  printed, copied into an artifact, or retained in a shared SDK cache.

## Runtime design

`luci-app-newt` depends on `newt`; users install one LuCI package name. The
architecture-independent UI calls the `luci.newt` ucode object through ubus
JSON-RPC. That object exposes only allowlisted methods and never returns secret
values. UCI state is persisted in `/etc/config/newt` with mode `0600`.

The init script validates configuration, renders Newt's JSON schema to
`/var/run/newt/config.json` under umask `077`, and gives only that path to the
process. `procd` captures stdout/stderr, applies a bounded respawn policy, and
starts at boot. `/var/run/newt/healthy` is the connected-state signal.

For provisioning, Newt replaces the one-time key in the runtime JSON with its
generated ID/secret. The supervised ucode helper copies the permanent values
back into UCI, switches to credential mode, and removes the key. The upstream
source patch removes debug messages that otherwise expose auth tokens or the
provisioning response body.

`NEWT_SYSTEM_SUBSTRATE=CONTAINER` is intentionally supplied to disable Newt's
in-place self-updater. APK owns `/usr/bin/newt`; self-modification would break
package integrity and reproducibility.

## Enrollment decision

Newt 1.18.1 supports either an existing ID/secret or a provisioning key plus
site name. The released Newt config schema and registration code contain no
approval-only anonymous join mode. The LuCI app and first-boot examples expose
both supported forms. Prefer a unique, scoped, short-lived provisioning key for
zero-touch images. Never publish a credential-bearing firmware image.

## Build and verification

On a workstation with Rancher Desktop or Docker and binfmt/QEMU support:

```sh
./tests/check.sh
./scripts/build-in-docker.sh
./scripts/verify-artifacts-in-docker.sh
./scripts/build-r5c-image-in-docker.sh
```

The authoritative verification includes:

- the pinned Newt archive hash and security patch;
- the official OpenWrt SDK and ImageBuilder hashes;
- both APK signatures and signed `packages.adb`;
- exact package names, versions, dependencies, architecture, and modes;
- AArch64 ELF metadata and `newt --version` execution under QEMU;
- compilation of the ucode RPC backend with the target OpenWrt runtime;
- NanoPi R5C ext4 and squashfs sysupgrade images and package manifest.

The remaining acceptance test is physical hardware. Flash or install on an
R5C, validate both credential modes, kill Newt to exercise respawn, reboot,
confirm reconnection, inspect LuCI network responses for secret absence, and
pass real HTTP/TCP traffic through a Pangolin resource.

## Release process

1. Check official OpenWrt downloads and the upstream Newt latest release.
2. For a Newt bump, update its version and archive hash in
   `packages/newt/Makefile`, rebase the log-redaction patch, and compare every
   `fileSettings` field in upstream `newtconfig/newtconfig.go` with
   `docs/CONFIGURATION.md` and `newt.init`.
3. Update hard-coded artifact expectations in the verification and image
   scripts. Increment `PKG_RELEASE` for packaging-only changes; reset it for a
   new upstream version.
4. For an OpenWrt bump, update both official archive names and SHA-256 values,
   the cache key, documentation, and expected target manifest. Never reuse an
   SDK or package feed across OpenWrt release lines without rebuilding.
5. Run all four commands in the previous section from a clean checkout.
6. Commit and push `main`; wait for CI.
7. Tag `v<newt-version>-openwrt<revision>` only after the branch build is
   green. A tag build signs and publishes the feed, APKs, images, checksums,
   and manifest to the GitHub release.
8. Download the public release artifacts and verify the signed feed again,
   independently of the Actions workspace.

The repository secret `OPENWRT_APK_PRIVATE_KEY_B64` contains the stable private
key. CI decodes it only into the runner temp directory. The build copies it
into the SDK only for signing and deletes it with a trap before the SDK cache
is saved. Key rotation requires publishing the new public key and fingerprint,
updating both first-boot scripts/docs, and providing an explicit migration path
for already-installed routers.

## Documentation policy

The README is intentionally short. Canonical detailed documentation remains in
`docs/` instead of a separate GitHub Wiki so it is versioned with each release,
reviewed in the same pull request, and cannot drift from the code. If a Wiki is
added later, generate it from these files rather than maintaining a second
manual source.

## Known constraints

- Only `aarch64_generic` packages and R5C images are currently published.
- The public Firmware Selector cannot resolve this external package in its
  package box; its first-boot script adds the signed feed after networking is
  available.
- The endpoint is HTTPS-only by policy. A nonstandard port belongs in the URL.
- The LuCI package manager has had problems installing untrusted uploaded APKs
  on OpenWrt 25.12. Install the public key first or use the signed feed.
- Advanced native WireGuard, Docker discovery, auth-daemon, mTLS, and metrics
  controls mirror upstream but have not all been exercised on physical R5C
  hardware. Userspace networking remains the default.
