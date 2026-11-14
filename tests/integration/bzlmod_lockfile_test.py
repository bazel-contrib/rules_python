from __future__ import annotations

import contextlib
import difflib
import os
import pathlib
import unittest
from collections.abc import Iterator

from tests.integration import runner


@contextlib.contextmanager
def _preserve_file(path: pathlib.Path) -> Iterator[bytes]:
    """Saves `path`'s contents and timestamps and restores them on exit.

    Integration tests run with `no-sandbox`, so `path` resolves into the source
    workspace. Restoring both bytes and `mtime` ensures `--flaky_test_attempts`
    retries do not observe in-place updates (or hit Skyframe's `mtime` cache)
    and local runs do not dirty the working tree.

    Args:
        path: File whose bytes and timestamps should be preserved.

    Yields:
        The original raw bytes of `path`.
    """
    original_stat = path.stat()
    original_bytes = path.read_bytes()
    try:
        yield original_bytes
    finally:
        path.write_bytes(original_bytes)
        os.utime(path, ns=(original_stat.st_atime_ns, original_stat.st_mtime_ns))


class BzlmodLockfileTest(runner.TestCase):
    def test_bzlmod_lockfile(self):
        lockfile_path = self.repo_root / "MODULE.bazel.lock"
        self.assertTrue(
            lockfile_path.exists(),
            f"Expected lockfile at {lockfile_path}",
        )

        res = self.run_bazel("test", "//...", check=False)
        if res.exit_code == 0:
            return

        # Generate updated lockfile to compare diff and export artifact
        with _preserve_file(lockfile_path) as original_bytes:
            self.run_bazel("mod", "deps", "--lockfile_mode=update", check=False)
            if lockfile_path.exists():
                updated_bytes = lockfile_path.read_bytes()
            else:
                updated_bytes = b""

        original_lockfile = original_bytes.decode("utf-8")
        updated_lockfile = updated_bytes.decode("utf-8")

        out_dir: pathlib.Path | None = None
        undeclared_outputs_dir = os.environ.get("TEST_UNDECLARED_OUTPUTS_DIR")
        if undeclared_outputs_dir:
            out_dir = pathlib.Path(undeclared_outputs_dir)
            (out_dir / "MODULE.bazel.lock").write_bytes(updated_bytes)

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

            if out_dir is not None:
                (out_dir / "MODULE.bazel.lock.diff").write_text(
                    diff_str, encoding="utf-8"
                )

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
