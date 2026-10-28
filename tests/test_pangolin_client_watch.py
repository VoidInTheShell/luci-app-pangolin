#!/usr/bin/env python3
"""Exercise the actual watcher shell with disposable commands and paths."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class ClientWatchTest(unittest.TestCase):
    def test_error_details_deduplication_and_recovery(self):
        with tempfile.TemporaryDirectory() as directory:
            temp = Path(directory)
            commands = temp / "bin"
            commands.mkdir()

            def executable(name, body):
                path = commands / name
                path.write_text("#!/bin/sh\nset -eu\n" + body)
                path.chmod(0o755)
                return str(path)

            integration = executable("integration", '''
count=0
[ ! -f "$TEST_COUNT" ] || count="$(cat "$TEST_COUNT")"
count=$((count + 1))
printf '%s\n' "$count" > "$TEST_COUNT"
case "$count" in
    1|2) echo 'Refusing to replace existing network.pangolin_client.' >&2; exit 1;;
    3) echo 'Save pending firewall changes before Pangolin integration.' >&2; exit 1;;
    *) exit 0;;
esac
''')
            dns = executable("dns", "exit 0\n")
            executable("curl", "exit 1\n")
            executable("logger", 'printf "%s\\n" "$*" >> "$TEST_LOG"\n')
            executable("sleep", '''
if [ "$(cat "$TEST_COUNT")" -ge 5 ]; then kill -TERM "$PPID"; fi
''')
            source = (ROOT / "packages/pangolin-cli/files/pangolin-client-watch").read_text()
            source = source.replace("/usr/libexec/pangolin-client-integration", integration)
            source = source.replace("/usr/libexec/pangolin-dns", dns)
            source = source.replace("/var/run/pangolin", str(temp / "runtime"))
            watcher = temp / "watcher"
            watcher.write_text(source)
            env = dict(os.environ, PATH=f"{commands}:{os.environ['PATH']}",
                       TEST_COUNT=str(temp / "count"), TEST_LOG=str(temp / "log"))
            result = subprocess.run(["/bin/sh", str(watcher)], env=env,
                                    capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual((temp / "count").read_text().strip(), "5")
            messages = (temp / "log").read_text().splitlines()
            self.assertEqual(len(messages), 3, messages)
            self.assertIn("Refusing to replace existing network.pangolin_client.", messages[0])
            self.assertIn("Save pending firewall changes", messages[1])
            self.assertIn("integration recovered", messages[2])


if __name__ == "__main__":
    unittest.main()
