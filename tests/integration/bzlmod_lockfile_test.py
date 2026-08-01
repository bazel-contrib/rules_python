import difflib
import os
import pathlib
import unittest

from tests.integration import runner


class BzlmodLockfileTest(runner.TestCase):
    def test_bzlmod_lockfile(self):
        lockfile_path = self.repo_root / "MODULE.bazel.lock"
        self.assertTrue(
            lockfile_path.exists(),
            f"Expected lockfile at {lockfile_path}",
        )
        original_lockfile = lockfile_path.read_text()

        res = self.run_bazel("test", "//...", check=False)
        if res.exit_code == 0:
            return

        # Generate updated lockfile to compare diff and export artifact
        self.run_bazel("mod", "deps", "--lockfile_mode=update", check=False)
        updated_lockfile = lockfile_path.read_text() if lockfile_path.exists() else ""

        undeclared_outputs_dir = os.environ.get("TEST_UNDECLARED_OUTPUTS_DIR")
        if undeclared_outputs_dir:
            out_dir = pathlib.Path(undeclared_outputs_dir)
            (out_dir / "MODULE.bazel.lock").write_text(updated_lockfile)

        if original_lockfile != updated_lockfile:
            diff_lines = list(
                difflib.unified_diff(
                    original_lockfile.splitlines(keepends=True),
                    updated_lockfile.splitlines(keepends=True),
                    fromfile="MODULE.bazel.lock (checked-in)",
                    tofile="MODULE.bazel.lock (expected/updated)",
                )
            )
            diff_str = "".join(diff_lines)

            if undeclared_outputs_dir:
                (out_dir / "MODULE.bazel.lock.diff").write_text(diff_str)

            msg = (
                f"MODULE.bazel.lock is out of date.\n\n"
                f"--- DIFF ---\n{diff_str}\n"
                f"--- END DIFF ---\n\n"
                f"To update the lockfile, run:\n"
                f"  bazel mod deps --lockfile_mode=update\n"
                f"inside tests/integration/bzlmod_lockfile, or copy the updated MODULE.bazel.lock artifact.\n"
            )
            self.fail(msg)
        else:
            self.fail(f"bazel test //... failed:\n{res.describe()}")


if __name__ == "__main__":
    unittest.main()
