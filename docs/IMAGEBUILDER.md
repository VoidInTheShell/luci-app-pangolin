# NanoPi R5C ImageBuilder and first boot

The normal installation path is the signed APK feed described in the main
README. A custom image is useful for unattended or repeatable deployments.
The image should contain `newt` and `luci-app-newt`, but normally should not
contain a Pangolin credential.

## Build an R5C image

Download the official OpenWrt 25.12.5 `rockchip/armv8` ImageBuilder on a Linux
x86-64 host and verify its checksum against the release `sha256sums` file. Copy
the two locally built APKs and the signed `packages.adb` into a local repository
served over HTTPS, or make them available to ImageBuilder through its local
package directory.

The NanoPi R5C profile name is `friendlyarm_nanopi-r5c`. A typical ImageBuilder
invocation is:

```sh
make image \
  PROFILE=friendlyarm_nanopi-r5c \
  PACKAGES='luci luci-app-newt' \
  FILES="$PWD/files"
```

`luci-app-newt` pulls in `newt` and its runtime dependencies. Keep LuCI itself
in `PACKAGES` because the stock non-LuCI image does not necessarily include the
web interface.

To preconfigure the endpoint, copy the example into the ImageBuilder overlay:

```sh
install -D -m 0755 \
  examples/uci-defaults/90-newt \
  files/etc/uci-defaults/90-newt
```

Edit `PANGOLIN_ENDPOINT` in the copied file. It is the complete public HTTPS
URL; append `:port` only for a non-default external port. With all credential
values empty, Newt is installed and boot-enabled but remains disabled until
someone finishes setup under **Services → Pangolin Newt**.

## Per-device zero-touch provisioning

Newt 1.18.1 supports two authentication forms: a Newt ID/secret pair, or a
Pangolin provisioning key plus a site name. Its released configuration and
registration protocol do not expose an approval-only enrollment flow. A
one-time provisioning key is the preferred unattended bootstrap mechanism.

For a private image generated for exactly one router, set these three values in
`files/etc/uci-defaults/90-newt`:

```sh
PANGOLIN_ENDPOINT='https://pangolin.example.com:8443'
NEWT_PROVISIONING_KEY='replace-with-a-unique-one-time-key'
NEWT_SITE_NAME='branch-r5c-001'
NEWT_ID=''
NEWT_SECRET=''
```

On first boot the script writes a root-only UCI configuration and starts Newt.
After Pangolin provisions the site, the credential-sync helper stores the
generated Newt ID and secret, clears the provisioning key, and switches the UCI
authentication mode to `credentials`.

Treat the resulting firmware as secret material. Deleting a first-boot script
from the writable overlay does not remove its bytes from the squashfs image.
Use a unique, narrowly scoped, short-lived key per image; revoke it after
enrollment. Never publish or reuse a credential-bearing image.

## Post-boot automation without a baked secret

The safer automated path is to install a generic image and inject a root-only
configuration file over SSH after first boot:

```sh
scp newt-bootstrap.env root@192.168.1.1:/tmp/newt-bootstrap.env
ssh root@192.168.1.1 'chmod 600 /tmp/newt-bootstrap.env && \
  /usr/libexec/configure-newt /tmp/newt-bootstrap.env && \
  rm -f /tmp/newt-bootstrap.env'
```

The installed package provides `/usr/libexec/configure-newt` for this purpose.
Do not put credentials on a command line because other local processes can
observe process arguments.

## First-boot feed configuration

To let a generated image install from the public feed on first boot instead of
embedding the APKs, include the repository signing public key under
`files/etc/apk/keys/` and place the full `packages.adb` URL in
`files/etc/apk/repositories.d/customfeeds.list`. OpenWrt 25.12 repository entries
point to the database file itself, for example:

```text
https://github.com/alexanderjlynn/openwrt-newt/releases/latest/download/packages.adb
```

Because `uci-defaults` runs before normal network startup, do not assume an
inline `apk update` can reach that feed. Use the supervised bootstrap described
below, or embed the packages with ImageBuilder. Embedding is the most reliable
first-boot method because it does not depend on WAN availability.

## OpenWrt Firmware Selector

The public [OpenWrt Firmware Selector](https://firmware-selector.openwrt.org/)
can add packages from official OpenWrt repositories and embed an
`/etc/uci-defaults` script. This project is an external feed, so the public
selector cannot resolve `luci-app-newt` from its **Installed Packages** box.
Use the signed-feed bootstrap instead:

1. Select **FriendlyARM NanoPi R5C** and OpenWrt 25.12.5.
2. Expand **Customize installed packages and/or first boot script**.
3. Keep the device's default package list; add `luci` if the list does not
   already contain it.
4. Paste the complete contents of
   `examples/uci-defaults/99-newt-from-feed` into **Script to run on first
   boot (uci-defaults)**.
5. Edit only the variable block at the top. `PANGOLIN_ENDPOINT` is a complete
   URL such as `https://pangolin.example.com` or
   `https://pangolin.example.com:8443`.
6. Choose one credential mode:
   - zero-touch: set a unique `NEWT_PROVISIONING_KEY` and `NEWT_SITE_NAME`;
   - existing site: set both `NEWT_ID` and `NEWT_SECRET`; or
   - configure later: leave all four credential variables empty.
7. Request the build, verify the displayed SHA-256 hash, and install the image
   using OpenWrt's normal device-specific procedure.

OpenWrt executes `uci-defaults` before normal network startup, so the script
does not download packages inline. It installs and starts a temporary
`newt-feed-bootstrap` procd service. That service waits and retries for up to
15 minutes, verifies the downloaded public key against the pinned SHA-256,
adds the signed feed, installs `luci-app-newt` and `newt`, applies the selected
credentials, and removes its own bootstrap files after success. If all retries
fail, the service remains enabled and runs again on the next boot.

Watch bootstrap progress after SSH becomes available:

```sh
logread -f -e newt-feed-bootstrap
```

After success, refresh LuCI and open **Services → Pangolin Newt**. A no-secret
image installs the app but leaves it disabled for interactive setup.

Anything pasted into a Firmware Selector first-boot script is embedded in the
downloaded image. An endpoint is normally safe to embed. Provisioning keys,
IDs, and secrets are sensitive even though the temporary writable bootstrap
files delete themselves. Use a unique short-lived key and never share or
publish a credential-bearing image.
