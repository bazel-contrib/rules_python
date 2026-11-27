"""Integration test for --bootstrap_impl in the exec configuration.

Verifies that a py_binary run by a genrule uses the bootstrap set with
--bootstrap_impl on the command line. Bazel 10 resets Starlark flags in the
exec configuration unless they have universal scope.
"""

import pathlib
import unittest

from tests.integration import runner


class BootstrapImplExecConfigTest(runner.TestCase):
    def test_genrule_tool_uses_bootstrap_script(self):
        """The launcher of the genrule tool is the script bootstrap."""
        self.run_bazel(
            "build",
            "--@rules_python//python/config_settings:bootstrap_impl=script",
            "//:tool_launcher",
        )
        execution_root = self.run_bazel("info", "execution_root").stdout.strip()
        result = self.run_bazel(
            "cquery",
            "--@rules_python//python/config_settings:bootstrap_impl=script",
            "--output=files",
            "//:tool_launcher",
        )
        launcher = pathlib.Path(execution_root, result.stdout.strip())
        self.assertEqual(launcher.read_text().strip(), "#!/usr/bin/env bash")


if __name__ == "__main__":
    unittest.main()
