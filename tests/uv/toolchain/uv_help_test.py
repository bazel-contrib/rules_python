#!/usr/bin/env python

import os
import subprocess
import unittest
from pathlib import Path

from python.runfiles import runfiles


class TestUV(unittest.TestCase):
    def test_uv_help(self):
        rfiles = runfiles.Create()
        assert rfiles is not None, "rfiles creation failed"

        data_rpath = os.environ["DATA"]
        uv_help_path = rfiles.Rlocation(data_rpath)
        assert uv_help_path is not None, (
            f"the rlocation path was not found: {data_rpath}"
        )

        uv_help = Path(uv_help_path).read_text()

        self.assertIn("Usage: uv [OPTIONS] <COMMAND>", uv_help)

    def test_uv_bin(self):
        root = runfiles.CreateOrRaise().root()

        for env_var in (
            "UV_BIN",
            "UV_CURRENT_TOOLCHAIN",
            "UV_RULES_PYTHON_BIN",
            "UV_RULES_PYTHON_UV",
        ):
            with self.subTest(env_var=env_var):
                uv_bin_path = root / os.environ[env_var]
                result = subprocess.run(
                    [uv_bin_path, "--python-fetch", "manual", "--help"],
                    capture_output=True,
                    text=True,
                    check=True,
                )
                self.assertIn("Usage: uv [OPTIONS] <COMMAND>", result.stdout)


if __name__ == "__main__":
    unittest.main()
