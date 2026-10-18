import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('release_version', Path(__file__).resolve().parents[1] / 'scripts/release-version.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class ReleaseVersionTests(unittest.TestCase):
    def test_dev_and_retry_are_distinct(self):
        a = module.resolve('1.1.0', 'refs/heads/dev', 17, 1)
        b = module.resolve('1.1.0', 'refs/heads/dev', 17, 2)
        self.assertEqual(a['version'], '1.1.0_pre17')
        self.assertNotEqual(a['tag'], b['tag'])
        self.assertNotEqual(a['revision'], b['revision'])
        self.assertTrue(a['prerelease'])

    def test_stable_matches_product_version(self):
        self.assertEqual(module.resolve('1.1.0', 'refs/tags/v1.1.0', 18, 1),
                         dict(tag='v1.1.0', version='1.1.0', revision='0', prerelease=False))

    def test_mismatched_or_development_tag_is_rejected(self):
        for tag in ['v1.2.0', 'v1.1.0-dev.17.1', 'v01.1.0']:
            with self.assertRaises(ValueError):
                module.resolve('1.1.0', 'refs/tags/' + tag, 18, 1)


if __name__ == '__main__':
    unittest.main()
