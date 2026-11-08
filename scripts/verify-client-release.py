#!/usr/bin/env python3
"""Verify SDK artifacts before uploading a release, including target execution."""
import hashlib
import json
import os
from pathlib import Path
import stat
import struct
import subprocess
import tempfile

repo = Path(__file__).resolve().parents[1]
arch = os.environ['OPENWRT_PACKAGE_ARCH']
target = os.environ['OPENWRT_TARGET']
subtarget = os.environ['OPENWRT_SUBTARGET']
openwrt = os.environ.get('OPENWRT_VERSION', '25.12.5')
is_ipk = openwrt.startswith('24.10.')
product_version = os.environ['PANGOLIN_PACKAGE_VERSION']
if is_ipk:
    product_version = product_version.replace('_pre', '~pre')
version = product_version + '-r' + os.environ['PANGOLIN_PACKAGE_RELEASE']
gcc = '13.3.0' if is_ipk else '14.3.0'
sdk = Path(os.environ.get('OPENWRT_SDK_DIR', repo / '.cache' / f'openwrt-sdk-{openwrt}-{target}-{subtarget}_gcc-{gcc}_musl.Linux-x86_64'))
apk = sdk / 'staging_dir/host/bin/apk'
output = repo / f'dist/openwrt-{openwrt}' / arch
key = output / 'pangolin-public-key.pem'
assert key.read_bytes() == Path(os.environ['OPENWRT_PUBLIC_KEY_FILE']).read_bytes()


def run(*args, **kwargs):
    return subprocess.check_output([str(a) for a in args], text=True, **kwargs).strip()


if is_ipk:
    packages = [output / f'pangolin-cli_{version}_{arch}.ipk', output / f'luci-app-pangolin_{version}_all.ipk']
    run('openssl', 'dgst', '-sha256', '-verify', key, '-signature', output / 'packages-sha256sums.sig', output / 'packages-sha256sums')
else:
    packages = [output / f'{name}-{version}.apk' for name in ['pangolin-cli', 'luci-app-pangolin']]
    run(apk, 'verify', '--keys-dir', output, *packages, output / 'packages.adb')
subprocess.run(['sha256sum', '-c', 'packages-sha256sums'], cwd=output, check=True)
with tempfile.TemporaryDirectory(prefix='pangolin-verify-') as work:
    work = Path(work)
    for package in packages:
        if is_ipk:
            # OpenWrt IPKs are tar containers with control/data tarballs.
            unpack = work / package.stem
            unpack.mkdir()
            run('tar', '-xf', package, '-C', unpack)
            control_dir = unpack / 'control-files'
            control_dir.mkdir()
            run('tar', '-xf', unpack / 'control.tar.gz', '-C', control_dir)
            control = dict(line.split(': ', 1) for line in (control_dir / 'control').read_text().splitlines() if ': ' in line)
            info = dict(name=control['Package'], version=control['Version'], arch=control['Architecture'],
                        depends=[d.strip().split(' ')[0] for d in control.get('Depends', '').split(',')])
        else:
            info = json.loads(run(apk, 'adbdump', '--format', 'json', package))['info']
        assert info['version'] == version, info
        expected_arch = arch if info['name'] == 'pangolin-cli' else ('all' if is_ipk else 'noarch')
        assert info['arch'] == expected_arch, info
        root = work / info['name']
        root.mkdir()
        if is_ipk:
            run('tar', '-xf', unpack / 'data.tar.gz', '-C', root)
        else:
            run(apk, 'extract', '--keys-dir', output, '--destination', root, package)
        for path in root.rglob('*'):
            if not path.is_file():
                continue
            blob = path.read_bytes()
            if blob.startswith(b'#!'):
                assert b'\r\n' not in blob, path
                assert stat.S_IMODE(path.stat().st_mode) & 0o111, path
        assert not list(root.rglob('accounts.json'))
        if info['name'] == 'pangolin-cli':
            assert {'kmod-tun', 'ucode-mod-fs', 'ucode-mod-uci', 'curl'} <= set(info['depends'])
            assert stat.S_IMODE((root / 'etc/config/pangolin').stat().st_mode) == 0o600
            binary = root / 'usr/bin/pangolin'
            blob = binary.read_bytes()
            assert blob[:6] == b'\x7fELF\x02\x01'
            assert struct.unpack_from('<H', blob, 18)[0] == (183 if arch.startswith('aarch64_') else 62)
            platform = os.environ['TARGET_PLATFORM']
            cmd = ['docker', 'run', '--rm', '--network', 'none', '--platform', platform,
                   '-v', f'{root}:/payload:ro', 'debian:bookworm-slim', '/payload/usr/bin/pangolin']
            assert run(*cmd, 'version') == '0.18.1'
            help_text = run(*cmd, 'up', 'client', '--help')
            for flag in ['--dns-listen', '--disable-dns', '--subnet-router', '--prefer-local-routes']:
                assert flag in help_text, flag
    # Compile with the actual OpenWrt runtime, including its fs/uci/ubus modules.
    sdk_root = next((sdk / 'staging_dir').glob('target-*/root-*'))
    loader = next((sdk_root / 'lib').glob('ld-musl-*.so.1'))
    paths = list((repo / 'packages/luci-app-pangolin/root/usr/share/rpcd/ucode').glob('*'))
    paths += list((repo / 'packages/pangolin-cli/files').glob('*.uc'))
    for path in paths:
        run('docker', 'run', '--rm', '--platform', os.environ['TARGET_PLATFORM'],
            '-v', f'{sdk_root}:/openwrt:ro', '-v', f'{repo}:/source:ro', 'debian:bookworm-slim',
            f'/openwrt/lib/{loader.name}', '--library-path', '/openwrt/usr/lib:/openwrt/lib',
            '/openwrt/usr/bin/ucode', '-L', '/openwrt/usr/lib/ucode', '-c', '-o', '/tmp/check.ucb',
            '/source/' + str(path.relative_to(repo)))

manifest = dict(source=os.environ['GITHUB_SHA'], product_version=version, openwrt=openwrt,
                architecture=arch, cli='0.18.1', newt='1.18.1', olm='1.10.1',
                packages={p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in packages})
(output / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
(output / 'INSTALL.txt').write_text('''Pangolin client for OpenWrt 25.12.5 (APK v3)

Use only the archive matching `apk --print-arch` (aarch64_generic or x86_64).
Verify the archive and public key against the release SHA256SUMS first.
Copy these extracted files into /tmp/pangolin-release on the router, then:

cd /tmp/pangolin-release
sha256sum -c packages-sha256sums
cp pangolin-public-key.pem /etc/apk/keys/pangolin-public-key.pem
apk add ./pangolin-cli-*.apk ./luci-app-pangolin-*.apk
/etc/init.d/rpcd restart

Install both packages; the LuCI package alone does not pull in pangolin-cli.
No separate Newt or OLM installation is needed.
Open LuCI -> VPN -> Pangolin. Save the server address, then authenticate.
Successful authentication automatically enables and starts the service.
DNS is disabled by default; the optional listener defaults to 127.0.0.1:953.
The signing key is specific to VoidInTheShell/luci-app-pangolin.
No credentials or device configuration are bundled. Installation does not start the VPN.
''')
if is_ipk:
    (output / 'INSTALL.txt').write_text(f'''Pangolin client for OpenWrt {openwrt} (IPK / opkg)

Use only the archive matching opkg print-architecture ({arch}).
Verify the public key against a trusted release key before using it.
On a computer with OpenSSL, verify the detached checksum signature:
openssl dgst -sha256 -verify pangolin-public-key.pem -signature packages-sha256sums.sig packages-sha256sums

On the router, extract to /tmp/pangolin-release, then:
cd /tmp/pangolin-release
sha256sum -c packages-sha256sums
opkg update
opkg install ./pangolin-cli_*.ipk ./luci-app-pangolin_*.ipk
/etc/init.d/rpcd restart

This is a local IPK bundle, not a usign-signed opkg feed.
Dependencies (including kmod-tun) must come from the router's own firmware feeds.
Both IPKs declare dependencies; opkg installs missing packages from those feeds.
Offline installation also requires local copies of every missing dependency.
Install both IPKs; the LuCI IPK alone does not pull in pangolin-cli.
No separate Newt or OLM installation is needed.
Do not install an SDK's kernel modules on a different kernel build.
Open LuCI -> VPN -> Pangolin, save the server address, then authenticate.
Successful authentication automatically enables and starts the service.
DNS is disabled by default. No credentials or device configuration are bundled.
''')
print(f'Verified signed {arch} packages {version} and target CLI/ucode execution.')
