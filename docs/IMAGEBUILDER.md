# NanoPi R5C images and first boot

The signed feed in [INSTALLING.md](INSTALLING.md) is the normal deployment.
Custom images are useful for repeatable or unattended routers. Never publish an
image that contains a Pangolin secret.

## Local ImageBuilder

After building the packages, run:

```sh
./scripts/build-r5c-image-in-docker.sh
```

The script uses the checksum-pinned OpenWrt 25.12.5 `rockchip/armv8`
ImageBuilder and profile `friendlyarm_nanopi-r5c`. It includes `luci` and
`luci-app-pangolin`; APK resolves `pangolin-cli`, `kmod-tun`, and the runtime
dependencies. Images and manifests are written below
`dist/openwrt-25.12.5/aarch64_generic/images/`.

To embed the package's first-boot setup in a local ImageBuilder overlay:

```sh
install -D -m 0755 \
  examples/uci-defaults/90-pangolin \
  files/etc/uci-defaults/90-pangolin
```

Edit only the variable block in the copied file.

## Public OpenWrt Firmware Selector

The public [OpenWrt Firmware Selector](https://firmware-selector.openwrt.org/)
cannot add this external feed during its package build. The repository provides
a late-network bootstrap:

1. Select **FriendlyARM NanoPi R5C** and OpenWrt 25.12.5.
2. Expand **Customize installed packages and/or first boot script**.
3. Keep the default packages and add `luci` if it is absent.
4. Paste all of `examples/uci-defaults/99-pangolin-from-feed` into **Script to
   run on first boot (uci-defaults)**.
5. Edit the variable block.
6. Request the image and verify the Firmware Selector SHA-256 before flashing.

The first-boot script creates a temporary `procd` worker because normal network
access may not exist during `uci-defaults`. It retries installation, verifies
the repository key against the pinned SHA-256, installs
`luci-app-pangolin`, applies configuration, and removes writable bootstrap
files after success. Monitor it with:

```sh
logread -f -e pangolin-feed-bootstrap
```

## Variable block

Use the public Pangolin HTTPS address and port:

```sh
PANGOLIN_ENDPOINT='https://pangolin.example.com:8443'

# Preferred for unattended first boot:
NEWT_PROVISIONING_KEY='unique-short-lived-key'
NEWT_SITE_NAME='branch-r5c-001'

# Leave empty when provisioning:
NEWT_ID=''
NEWT_SECRET=''

# Leave off unless deliberately testing the upstream native-main mode:
PANGOLIN_NATIVE_MAIN='0'
```

Port 443 needs no explicit suffix. Use an existing site pair instead when a
provisioning key is unavailable:

```sh
NEWT_PROVISIONING_KEY=''
NEWT_SITE_NAME=''
NEWT_ID='site-id'
NEWT_SECRET='site-secret'
```

With all credential values empty, the package and endpoint are installed but
the site remains disabled for later setup in **Services → Pangolin**. There is
no credential-free approval-only enrollment in the current site protocol.

## Safer post-deploy configuration

Instead of embedding credentials, transfer a mode-0600 file after first boot:

```sh
scp pangolin-bootstrap.env root@192.168.1.1:/tmp/pangolin-bootstrap.env
ssh root@192.168.1.1 'chmod 600 /tmp/pangolin-bootstrap.env && \
  /usr/libexec/configure-pangolin /tmp/pangolin-bootstrap.env && \
  rm -f /tmp/pangolin-bootstrap.env'
```

Example file:

```sh
PANGOLIN_ENDPOINT='https://pangolin.example.com'
NEWT_ID='site-id'
NEWT_SECRET='site-secret'
PANGOLIN_NATIVE_MAIN='0'
```

Anything pasted into Firmware Selector or placed in an ImageBuilder overlay is
recoverable from the generated image even after first boot deletes a writable
copy. Use one short-lived credential per router, revoke provisioning values
after enrollment, and treat credential-bearing images as secrets.
