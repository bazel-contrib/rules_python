import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from python import runfiles

LAUNCHER = sys.argv.pop(1)


class ToolchainRunfilesTest(unittest.TestCase):
    def test_lock_with_toolchain_runfiles(self):
        files = runfiles.Create()
        assert files is not None
        launcher = files.Rlocation(LAUNCHER)
        assert launcher is not None
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory, "tests/uv/lock/toolchain_requirements.txt")
            output.parent.mkdir(parents=True)
            env = dict(os.environ, BUILD_WORKSPACE_DIRECTORY=directory)
            env.update(files.EnvVars())
            env.pop("TEST_SRCDIR", None)
            command = [launcher]
            if os.name == "nt" and launcher.endswith(".bat"):
                command = ["cmd.exe", "/c", launcher]
            result = subprocess.run(command, env=env, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertEqual(output.read_text(), "custom uv toolchain runfiles\n")


if __name__ == "__main__":
    unittest.main()
