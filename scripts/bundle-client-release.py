#!/usr/bin/env python3
"""Export verified SDK output as tar.gz, ZIP and standalone package assets."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import tarfile
import zipfile


def bundle(source, output, tag, signing_key=None):
    manifest = json.loads((source / 'manifest.json').read_text())
    firmware = manifest['openwrt']
    arch = manifest['architecture']
    version = manifest['product_version']
    architectures = {'24.10.2': ('aarch64_generic', 'aarch64_cortex-a53', 'x86_64'),
                     '25.12.5': ('aarch64_generic', 'x86_64')}
    if arch not in architectures.get(firmware, ()):
        raise ValueError('Unsupported release platform')
    if not re.fullmatch(r'v[0-9][A-Za-z0-9._-]*', tag) or not re.fullmatch(r'[0-9][A-Za-z0-9._~+-]*', version):
        raise ValueError('Invalid release tag or package version')
    is_ipk = firmware.startswith('24.10.')
    package_names = ('pangolin-cli', 'luci-app-pangolin')
    packages = {
        name: (f'{name}_{version}_{arch if name == "pangolin-cli" else "all"}.ipk'
               if is_ipk else f'{name}-{version}.apk')
        for name in package_names
    }
    if set(manifest['packages']) != set(packages.values()):
        raise ValueError('Release must contain exactly the client and LuCI packages')
    metadata = {'INSTALL.txt', 'manifest.json', 'packages-sha256sums', 'pangolin-public-key.pem'}
    metadata |= {'Packages', 'Packages.gz', 'packages-sha256sums.sig'} if is_ipk else {'packages.adb', 'index.json'}
    filenames = set(packages.values()) | metadata
    if {p.name for p in source.iterdir()} != filenames:
        raise ValueError('Unexpected or missing files in verified release directory')
    for name in filenames:
        path = source / name
        if path.is_symlink() or not path.is_file():
            raise ValueError('Release inputs must be regular files')
    for name, digest in manifest['packages'].items():
        if hashlib.sha256((source / name).read_bytes()).hexdigest() != digest:
            raise ValueError(f'Package checksum mismatch: {name}')
    if is_ipk and (signing_key is None or not signing_key.is_file()):
        raise ValueError('Standalone IPK checksums require the release signing key')

    prefix = f'luci-app-pangolin-{tag}-openwrt-{firmware}-{arch}'
    # GitHub rewrites characters such as '~' in uploaded asset names.
    asset_version = re.sub(r'[^A-Za-z0-9._-]', '_', version)
    direct_names = {
        name: (f'{name}_{asset_version}_openwrt-{firmware}_{arch}.ipk' if is_ipk
               else f'{name}-{asset_version}-openwrt-{firmware}-{arch}.apk')
        for name in package_names
    }
    asset_names = [prefix + '.tar.gz', prefix + '.zip', *direct_names.values()]
    if is_ipk:
        asset_names += [prefix + '-ipk-SHA256SUMS', prefix + '-ipk-SHA256SUMS.sig']
    output.mkdir(parents=True, exist_ok=True)
    if any((output / name).exists() for name in asset_names):
        raise ValueError('Refusing to overwrite an existing release asset')
    with tarfile.open(output / (prefix + '.tar.gz'), 'w:gz') as archive:
        for name in sorted(filenames):
            archive.add(source / name, arcname='./' + name)
    with zipfile.ZipFile(output / (prefix + '.zip'), 'w', compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for name in sorted(filenames):
            archive.write(source / name, arcname=name)
    for name, original in packages.items():
        shutil.copyfile(source / original, output / direct_names[name])
    if is_ipk:
        sums = output / (prefix + '-ipk-SHA256SUMS')
        sums.write_text(''.join(
            hashlib.sha256((output / name).read_bytes()).hexdigest() + '  ' + name + '\n'
            for name in sorted(direct_names.values())
        ), encoding='utf-8')
        signature = output / (sums.name + '.sig')
        subprocess.run(['openssl', 'dgst', '-sha256', '-sign', str(signing_key),
                        '-out', str(signature), str(sums)], check=True)
        subprocess.run(['openssl', 'dgst', '-sha256', '-verify', str(source / 'pangolin-public-key.pem'),
                        '-signature', str(signature), str(sums)], check=True)
    return [output / name for name in asset_names]


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--input', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--tag', required=True)
    parser.add_argument('--signing-key', type=Path)
    args = parser.parse_args()
    for asset in bundle(args.input, args.output, args.tag, args.signing_key):
        print(asset.name)
