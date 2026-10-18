#!/usr/bin/env python3
"""Package an already cross-compiled, patched CLI with this checkout's files.

Runs on Linux as root using apk-tools 3 mkpkg. This is a development packaging
path; the SDK Makefiles remain the source build entry point.
"""
import argparse
import hashlib
import json
import os
import re
from pathlib import Path
import struct
import subprocess
import tempfile

p = argparse.ArgumentParser()
p.add_argument('--binary', type=Path, required=True)
p.add_argument('--arch', choices=['aarch64_generic', 'x86_64'], required=True)
p.add_argument('--apk-tool', type=Path, required=True)
p.add_argument('--output', type=Path)
args = p.parse_args()
repo = Path(__file__).resolve().parents[1]
if os.geteuid() != 0:
    p.error('run as root so APK file ownership is root:root')
header = args.binary.read_bytes()[:64]
if header[:5] != b'\x7fELF\x02' or struct.unpack_from('<H', header, 18)[0] != (183 if args.arch == 'aarch64_generic' else 62):
    p.error('binary must be a Linux ELF64 for the selected architecture')
out = args.output or repo / 'dist' / 'openwrt-25.12.5' / args.arch
out.mkdir(parents=True, exist_ok=True)

def copy(source, root, target, mode):
    dest = root / target.lstrip('/')
    dest.parent.mkdir(parents=True, exist_ok=True)
    data = source.read_bytes()
    # A local Windows checkout may still contain CRLF before Git normalizes
    # the files. Linux treats the CR in a shebang as part of the interpreter
    # path, so executable scripts must be normalized before APK creation.
    if data.startswith(b'#!'):
        data = data.replace(b'\r\n', b'\n')
    dest.write_bytes(data)
    dest.chmod(mode)

def package_version(name):
    makefile = (repo / 'packages' / name / 'Makefile').read_text()
    version = re.search(r'^PKG_VERSION:=(\S+)', makefile, re.M).group(1)
    release = re.search(r'^PKG_RELEASE:=(\S+)', makefile, re.M).group(1)
    return version + '-r' + release

def package(root, name, version, arch, description, depends, scripts):
    output = out / (name + '-' + version + '.apk')
    cmd = [str(args.apk_tool), 'mkpkg', '--files', str(root), '--output', str(output),
           '--info', 'name:' + name, '--info', 'version:' + version,
           '--info', 'arch:' + arch, '--info', 'description:' + description,
           '--info', 'license:' + ('AGPL-3.0-only' if name == 'pangolin-cli' else 'Apache-2.0'),
           '--info', 'origin:' + name,
           '--info', 'url:https://github.com/VoidInTheShell/luci-app-pangolin',
           '--info', 'depends:' + ' '.join(depends)]
    for kind, path in scripts.items():
        cmd += ['--script', kind + ':' + str(path)]
    subprocess.run(cmd, check=True)
    return output

with tempfile.TemporaryDirectory(prefix='pangolin-apk-') as tmp:
    tmp = Path(tmp)
    core, luci = tmp / 'core', tmp / 'luci'
    core.mkdir(); luci.mkdir()
    files = repo / 'packages/pangolin-cli/files'
    copy(args.binary, core, '/usr/bin/pangolin', 0o755)
    copy(files / 'pangolin.config', core, '/etc/config/pangolin', 0o600)
    for name in ['version', 'newt-version']:
        copy(files / name, core, '/usr/share/pangolin/' + name, 0o644)
    copy(files / 'pangolin.init', core, '/etc/init.d/pangolin', 0o755)
    copy(files / 'pangolin-auth.init', core, '/etc/init.d/pangolin-auth', 0o755)
    for name in ['pangolin-client-run', 'pangolin-client-watch', 'pangolin-client-integration',
                 'pangolin-client-integrate.uc', 'pangolin-locked', 'pangolin-dns', 'pangolin-dns.uc',
                 'pangolin-auth-run', 'pangolin-site-run', 'pangolin-service-action', 'pangolin-network',
                 'pangolin-site-sync-credentials', 'configure-pangolin']:
        copy(files / name, core, '/usr/libexec/' + name, 0o755)
    root = repo / 'packages/luci-app-pangolin/root'
    for source in root.rglob('*'):
        if source.is_file():
            relative = source.relative_to(root).as_posix()
            mode = 0o755 if relative.startswith(('usr/libexec/', 'usr/share/rpcd/ucode/')) else 0o644
            copy(source, luci, '/' + relative, mode)
    htdocs = repo / 'packages/luci-app-pangolin/htdocs'
    for source in htdocs.rglob('*'):
        if source.is_file():
            copy(source, luci, '/www/' + source.relative_to(htdocs).as_posix(), 0o644)
    post = tmp / 'post-install'
    post.write_text('#!/bin/sh\nchmod 0600 /etc/config/pangolin\n', encoding='utf-8')
    pre = tmp / 'pre-deinstall'
    pre.write_text('#!/bin/sh\n/etc/init.d/pangolin stop\n/etc/init.d/pangolin-auth stop\n/usr/libexec/pangolin-dns restore\n/usr/libexec/pangolin-client-integration restore\n', encoding='utf-8')
    paths = [
        package(core, 'pangolin-cli', package_version('pangolin-cli'), args.arch, 'Pangolin client with configurable DNS',
                ['ca-bundle', 'curl', 'jshn', 'kmod-tun', 'ucode', 'ucode-mod-fs', 'ucode-mod-uci'],
                {'post-install': post, 'post-upgrade': post, 'pre-deinstall': pre}),
        package(luci, 'luci-app-pangolin', package_version('luci-app-pangolin'), 'noarch', 'LuCI management for Pangolin client',
                ['luci-base', 'rpcd-mod-ucode', 'ucode-mod-fs', 'ucode-mod-uci', 'ucode-mod-ubus'], {})
    ]
manifest = [{'name': path.name, 'sha256': hashlib.sha256(path.read_bytes()).hexdigest()} for path in paths]
(out / 'development-manifest.json').write_text(json.dumps(manifest, indent=2) + '\n', encoding='utf-8')
print(json.dumps(manifest, indent=2))
