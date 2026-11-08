"""Verify archive parity, collision-free package exports and IPK signatures."""
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import subprocess
import tarfile
import tempfile
import unittest
import zipfile

script = Path(__file__).resolve().parents[1] / 'scripts/bundle-client-release.py'
spec = importlib.util.spec_from_file_location('bundle_client_release', script)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class ReleaseAssetTests(unittest.TestCase):
    def setUp(self):
        self.work = tempfile.TemporaryDirectory()
        self.addCleanup(self.work.cleanup)
        self.root = Path(self.work.name)
        self.key = self.root / 'test-signing.pem'
        subprocess.run(['openssl', 'ecparam', '-name', 'prime256v1', '-genkey', '-noout',
                        '-out', str(self.key)], check=True, capture_output=True)
        self.public = subprocess.check_output(['openssl', 'pkey', '-in', str(self.key), '-pubout'])

    def source(self, firmware, arch):
        path = self.root / firmware / arch
        path.mkdir(parents=True)
        ipk = firmware.startswith('24.10.')
        version = '1.1.0~pre1-r1' if ipk else '1.1.0_pre1-r1'
        packages = {}
        for name in ('pangolin-cli', 'luci-app-pangolin'):
            filename = (f'{name}_{version}_{arch if name == "pangolin-cli" else "all"}.ipk'
                        if ipk else f'{name}-{version}.apk')
            data = f'{name}:{firmware}:{arch}'.encode()
            (path / filename).write_bytes(data)
            packages[filename] = hashlib.sha256(data).hexdigest()
        manifest = dict(openwrt=firmware, architecture=arch, product_version=version, packages=packages)
        (path / 'manifest.json').write_text(json.dumps(manifest))
        for name in ['INSTALL.txt', 'packages-sha256sums',
                     *(['Packages', 'Packages.gz', 'packages-sha256sums.sig'] if ipk else ['packages.adb', 'index.json'])]:
            (path / name).write_bytes(('fixture:' + name).encode())
        (path / 'pangolin-public-key.pem').write_bytes(self.public)
        return path

    def test_all_platforms_keep_both_packages_and_identical_archive_contents(self):
        output = self.root / 'assets'
        emitted = []
        for firmware, architectures in (
            ('24.10.2', ('aarch64_generic', 'aarch64_cortex-a53', 'x86_64')),
            ('25.12.5', ('aarch64_generic', 'x86_64')),
        ):
            for arch in architectures:
                source = self.source(firmware, arch)
                assets = module.bundle(source, output, 'v1.1.0-dev.1.1', self.key)
                self.assertTrue(all(re.fullmatch(r'[A-Za-z0-9._-]+', p.name) for p in assets))
                emitted.extend(assets)
                expected = {p.name: p.read_bytes() for p in source.iterdir()}
                with tarfile.open(next(p for p in assets if p.name.endswith('.tar.gz'))) as archive:
                    tar_contents = {m.name.removeprefix('./'): archive.extractfile(m).read() for m in archive.getmembers()}
                with zipfile.ZipFile(next(p for p in assets if p.suffix == '.zip')) as archive:
                    zip_contents = {name: archive.read(name) for name in archive.namelist()}
                self.assertEqual(tar_contents, expected)
                self.assertEqual(zip_contents, expected)
                direct = [p for p in assets if p.suffix in ('.ipk', '.apk')]
                self.assertEqual(len(direct), 2)
                self.assertEqual({p.read_bytes() for p in direct},
                                 {p.read_bytes() for p in source.iterdir() if p.suffix in ('.ipk', '.apk')})
                self.assertTrue(all(f'openwrt-{firmware}' in p.name and arch in p.name for p in direct))
                if firmware.startswith('24.10.'):
                    sums = next(p for p in assets if p.name.endswith('-ipk-SHA256SUMS'))
                    for line in sums.read_text().splitlines():
                        digest, filename = line.split()
                        self.assertEqual(hashlib.sha256((output / filename).read_bytes()).hexdigest(), digest)
                    subprocess.run(['openssl', 'dgst', '-sha256', '-verify', str(source / 'pangolin-public-key.pem'),
                                    '-signature', str(sums) + '.sig', str(sums)], check=True, capture_output=True)
        self.assertEqual(len(emitted), 26)
        self.assertEqual(len(set(p.name for p in emitted)), 26)

    def test_cortex_a53_is_only_supported_on_ipk_release(self):
        source = self.source('25.12.5', 'aarch64_cortex-a53')
        with self.assertRaisesRegex(ValueError, 'Unsupported release platform'):
            module.bundle(source, self.root / 'assets', 'v1.1.0-dev.1.1')
        self.assertFalse((self.root / 'assets').exists())

    def test_rejects_changed_package_before_export(self):
        source = self.source('25.12.5', 'x86_64')
        next(source.glob('pangolin-cli-*.apk')).write_bytes(b'tampered')
        with self.assertRaisesRegex(ValueError, 'checksum mismatch'):
            module.bundle(source, self.root / 'assets', 'v1.1.0-dev.1.1')
        self.assertFalse((self.root / 'assets').exists())

    def test_rejects_unexpected_private_file(self):
        source = self.source('24.10.2', 'aarch64_generic')
        (source / 'private-key.pem').write_bytes(b'not-a-real-key')
        with self.assertRaisesRegex(ValueError, 'Unexpected or missing files'):
            module.bundle(source, self.root / 'assets', 'v1.1.0-dev.1.1', self.key)


if __name__ == '__main__':
    unittest.main()
