"""Exercise the actual development packager copy boundary without apk or root."""
import ast
from pathlib import Path
import tempfile
import unittest


script = Path(__file__).resolve().parents[1] / 'scripts/package-client-prebuilt.py'
tree = ast.parse(script.read_text(encoding='utf-8'))
copy_function = next(node for node in tree.body if isinstance(node, ast.FunctionDef) and node.name == 'copy')
scope = {}
exec(compile(ast.Module(body=[copy_function], type_ignores=[]), str(script), 'exec'), scope)
copy = scope['copy']


class PackageFileTests(unittest.TestCase):
    def test_windows_script_is_executable_with_a_linux_interpreter(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / 'service-action'
            source.write_bytes(b'#!/bin/sh\r\nexec /etc/init.d/pangolin "$1"\r\n')
            copy(source, root / 'package', '/usr/libexec/service-action', 0o755)
            result = (root / 'package/usr/libexec/service-action').read_bytes()
            self.assertEqual(result.split(b'\n', 1)[0], b'#!/bin/sh')
            self.assertNotIn(b'\r\n', result)

    def test_cli_binary_is_preserved_byte_for_byte(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / 'pangolin'
            binary = b'\x7fELF\x02\x00\r\n\x00binary-content'
            source.write_bytes(binary)
            copy(source, root / 'package', '/usr/bin/pangolin', 0o755)
            self.assertEqual((root / 'package/usr/bin/pangolin').read_bytes(), binary)



if __name__ == '__main__':
    unittest.main()
