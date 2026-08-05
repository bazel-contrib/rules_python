import glob
import importlib.util
import os
import sys
import unittest

try:
    import echo_ext
except ModuleNotFoundError:
    echo_ext = None
    for path in sys.path:
        matches = glob.glob(os.path.join(path, "echo_ext*.*"))
        for m in matches:
            if m.endswith(".so") or m.endswith(".pyd"):
                spec = importlib.util.spec_from_file_location("echo_ext", m)
                echo_ext = importlib.util.module_from_spec(spec)
                spec.loader.exec_module(echo_ext)
                break
        if echo_ext:
            break
    if not echo_ext:
        raise ModuleNotFoundError("No module named 'echo_ext'")


class ExtensionTest(unittest.TestCase):
    def test_echo_extension(self):
        self.assertEqual(echo_ext.echo(42, "str"), tuple(42, "str"))
