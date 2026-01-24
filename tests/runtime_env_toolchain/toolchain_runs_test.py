import json
import pathlib
import platform
import sys
import unittest

from python.runfiles import runfiles


class RunTest(unittest.TestCase):
    def test_ran(self):
        rf = runfiles.Create()
        try:
            settings_path = rf.Rlocation(
                "rules_python/tests/support/current_build_settings.json"
            )
        except ValueError as e:
            # The current toolchain being used has a buggy zip file bootstrap, which
            # leaves RUNFILES_DIR pointing at the first stage path and not the module
            # path.
            if platform.system() != "Windows" or "does not lie under the runfiles root" not in str(e):
                raise e
            settings_path = "./tests/support/current_build_settings.json"

        settings = json.loads(pathlib.Path(settings_path).read_text())

        if platform.system() == "Windows":
            self.assertEqual(
                "/_magic_pyruntime_sentinel_do_not_use", settings["interpreter_path"]
            )
        else:
            self.assertIn(
                "runtime_env_toolchain_interpreter.sh",
                settings["interpreter"]["short_path"],
            )

        if settings["bootstrap_impl"] == "script":
            # Verify we're running in a venv
            self.assertNotEqual(sys.prefix, sys.base_prefix)
            # .venv/ occurs for a build-time venv.
            # For a runtime created venv, it goes into a temp dir, so
            # look for the /bin/ dir as an indicator.
            self.assertRegex(sys.executable, r"[.]venv/|/bin/")


if __name__ == "__main__":
    unittest.main()
