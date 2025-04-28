import os
import subprocess
import sys
import unittest
from typing import Iterable

from python import runfiles

rfiles = runfiles.Create()

# Signals the tests below whether we should be expecting the import of
# helpers/test_module.py on the REPL to work or not.
EXPECT_TEST_MODULE_IMPORTABLE = os.environ["EXPECT_TEST_MODULE_IMPORTABLE"] == "1"


class ReplTest(unittest.TestCase):
    def setUp(self):
        self.repl = rfiles.Rlocation("rules_python/python/bin/repl")
        assert self.repl

    def run_code_in_repl(self, lines: Iterable[str]) -> str:
        """Runs the lines of code in the REPL and returns the text output."""
        return subprocess.check_output(
            [self.repl],
            text=True,
            stderr=subprocess.STDOUT,
            input="\n".join(lines),
        ).strip()

    def test_repl_version(self):
        """Validates that we can successfully execute arbitrary code on the REPL."""

        result = self.run_code_in_repl(
            [
                "import sys",
                "v = sys.version_info",
                "print(f'version: {v.major}.{v.minor}')",
            ]
        )
        self.assertIn("version: 3.12", result)

    def test_cannot_import_test_module_directly(self):
        """Validates that we cannot import helper/test_module.py since it's not a direct dep."""
        with self.assertRaises(ModuleNotFoundError):
            import test_module

    @unittest.skipIf(
        not EXPECT_TEST_MODULE_IMPORTABLE, "test only works without repl_dep set"
    )
    def test_import_test_module_success(self):
        """Validates that we can import helper/test_module.py when repl_dep is set."""
        result = self.run_code_in_repl(
            [
                "import test_module",
                "test_module.print_hello()",
            ]
        )
        self.assertIn("Hello World", result)

    @unittest.skipIf(
        EXPECT_TEST_MODULE_IMPORTABLE, "test only works without repl_dep set"
    )
    def test_import_test_module_failure(self):
        """Validates that we cannot import helper/test_module.py when repl_dep isn't set."""
        result = self.run_code_in_repl(
            [
                "import test_module",
            ]
        )
        self.assertIn("ModuleNotFoundError: No module named 'test_module'", result)


if __name__ == "__main__":
    unittest.main()
