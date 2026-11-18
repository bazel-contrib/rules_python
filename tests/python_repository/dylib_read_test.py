"""Tests `dylib_id_is_rpath` on a dylib with bytes >= 0x80 read by `rctx.read`."""

import json
import os
import unittest
from pathlib import Path

from python.runfiles import runfiles


class DylibReadTest(unittest.TestCase):
    def _path(self, env_var):
        rpath = os.environ[env_var]
        path = runfiles.CreateOrRaise().Rlocation(rpath)
        assert path is not None, f"runfile not found: {rpath}"
        return Path(path)

    def test_dylib_has_high_bytes_on_disk(self):
        data = self._path("DYLIB").read_bytes()
        # mach_header_64 plus a 136-byte and a 64-byte load command.
        self.assertEqual(len(data), 32 + 200)
        self.assertEqual(data[20], 0xC8)  # sizeofcmds
        self.assertEqual(data[36], 0x88)  # cmdsize of the first command

    def test_dylib_id_is_rpath(self):
        result = json.loads(self._path("RESULT").read_text())
        self.assertEqual(result, {"dylib_id_is_rpath": True})


if __name__ == "__main__":
    unittest.main()
