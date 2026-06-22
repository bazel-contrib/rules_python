import os
import subprocess
import tempfile
import unittest
from pathlib import Path

from python import runfiles

rfiles = runfiles.Create()


def _relative_rpath(path: str) -> Path:
    """Find file in runfiles, handling Windows .bat/.exe wrappers."""
    # On Windows, try executable extensions first to avoid matching symlink
    # entries in the runfiles manifest that point to non-executable files
    # (e.g. a Python source file instead of the .exe launcher).
    exts = (".exe", ".bat", "") if os.name == "nt" else ("", ".exe", ".bat")
    for ext in exts:
        p = (Path("_main") / "tests" / "uv" / "lock" / (path + ext)).as_posix()
        rpath = rfiles.Rlocation(p)
        if rpath:
            rp = Path(rpath)
            if rp.exists():
                return rp

    # Fallback: look in runfiles directory directly (handles .bat wrappers on
    # Windows where Rlocation may return a runfiles link that doesn't exist)
    runfiles_dir = os.environ.get("RUNFILES_DIR")
    if runfiles_dir:
        exts = (".exe", ".bat", "") if os.name == "nt" else ("", ".bat", ".exe")
        for ext in exts:
            rp = Path(runfiles_dir, "_main", "tests", "uv", "lock", path + ext)
            if rp.exists():
                return rp

    raise ValueError(f"Could not find file in runfiles: {path}")


def _run_binary(path: Path, **kwargs):
    """Run a binary, handling Windows .bat files."""
    if os.name == "nt":
        return subprocess.run(
            ["cmd.exe", "/c", str(path)],
            **kwargs,
        )
    return subprocess.run(path, **kwargs)


class LockTests(unittest.TestCase):
    def _subprocess_env(self, workspace_dir: Path) -> dict[str, str]:
        env = {
            "BUILD_WORKSPACE_DIRECTORY": str(workspace_dir),
        }
        # Inherit specific env vars needed for finding runfiles on Windows
        for key in (
            "PATH",
            "RUNFILES_DIR",
            "RUNFILES_MANIFEST_FILE",
            "SYSTEMROOT",
            "PATHEXT",
        ):
            if key in os.environ:
                env[key] = os.environ[key]
        return env

    def test_requirements_run_script_for_new_file(self):
        """Verify the requirements_new_file.run script has expected args."""
        run_script_path = _relative_rpath("requirements_new_file.run")
        content = run_script_path.read_text()

        if os.name == "nt":
            self.assertIn("@echo off", content)
        else:
            self.assertIn("#!/usr/bin/env bash", content)
        self.assertIn("BUILD_WORKSPACE_DIRECTORY", content)
        self.assertIn("--no-progress", content)
        self.assertIn("--quiet", content)
        self.assertIn("does_not_exist.txt", content)

    def test_uv_lock_run_script(self):
        """Verify the uv_lock_test.run script has expected args."""
        run_script_path = _relative_rpath("uv_lock_test.run")
        content = run_script_path.read_text()

        if os.name == "nt":
            self.assertIn("@echo off", content)
        else:
            self.assertIn("#!/usr/bin/env bash", content)
        self.assertIn("--no-progress", content)
        self.assertIn("--quiet", content)

    def test_run_script_has_no_output_file_arg(self):
        """Verify the uv lock .run script does NOT have --output-file (uv lock doesn't use it)."""
        run_script_path = _relative_rpath("uv_lock_test.run")
        content = run_script_path.read_text()

        self.assertNotIn("--output-file", content)

    def test_debug_requirements_diff(self):
        """Temporary test to print diff of generated vs expected requirements on Windows."""
        expected_path = _relative_rpath("testdata/requirements.txt")
        try:
            # Pass "requirements.out" directly. We need to handle the case where
            # _relative_rpath might append extensions on Windows.
            # Actually, _relative_rpath has:
            # exts = (".exe", ".bat", "") if os.name == "nt" else ...
            # So on Windows it will try .exe, .bat, then empty.
            # If "requirements.out" exists, the empty extension will match it.
            generated_path = _relative_rpath("requirements.out")
        except ValueError as e:
            print(f"Could not find requirements.out: {e}")
            # Dump runfiles directory to help debug if needed
            runfiles_dir = os.environ.get("RUNFILES_DIR")
            if runfiles_dir:
                print(f"RUNFILES_DIR: {runfiles_dir}")
                for root, _, files in os.walk(runfiles_dir):
                    for f in files:
                        if "requirements" in f:
                            print(os.path.join(root, f))
            raise

        expected = expected_path.read_text()
        generated = generated_path.read_text()

        if expected != generated:
            import difflib

            diff = list(
                difflib.unified_diff(
                    expected.splitlines(keepends=True),
                    generated.splitlines(keepends=True),
                    fromfile="expected (testdata/requirements.txt)",
                    tofile="generated (requirements.out)",
                )
            )
            print("\n=== DIFF START ===")
            print("".join(diff))
            print("=== DIFF END ===\n")

            # Also print representation to see line endings
            print(f"Expected line endings: {repr(expected[:100])}")
            print(f"Generated line endings: {repr(generated[:100])}")

            self.assertEqual(expected, generated, "Files differ! See diff above.")

    def test_requirements_updating_for_the_first_time(self):
        # Given
        copier_path = _relative_rpath("requirements_new_file.update")

        # When
        with tempfile.TemporaryDirectory() as dir:
            workspace_dir = Path(dir)
            want_path = workspace_dir / "tests" / "uv" / "lock" / "does_not_exist.txt"

            self.assertFalse(
                want_path.exists(), "The path should not exist after the test"
            )
            output = _run_binary(
                copier_path,
                capture_output=True,
                env=self._subprocess_env(workspace_dir),
            )

            # Then
            self.assertEqual(0, output.returncode, output.stderr)
            stdout = output.stdout.decode("utf-8").replace("\\", "/")
            self.assertIn(
                "cp <bazel-sandbox>/tests/uv/lock/requirements_new_file",
                stdout,
            )
            self.assertTrue(want_path.exists(), "The path should exist after the test")
            self.assertNotEqual(want_path.read_text(), "")

    def test_requirements_updating(self):
        # Given
        copier_path = _relative_rpath("requirements.update")

        # When
        with tempfile.TemporaryDirectory() as dir:
            workspace_dir = Path(dir)
            want_path = (
                workspace_dir
                / "tests"
                / "uv"
                / "lock"
                / "testdata"
                / "requirements.txt"
            )
            want_path.parent.mkdir(parents=True)

            output = _run_binary(
                copier_path,
                capture_output=True,
                env=self._subprocess_env(workspace_dir),
            )

            # Then
            self.assertEqual(0, output.returncode)
            stdout = output.stdout.decode("utf-8").replace("\\", "/")
            self.assertIn(
                "cp <bazel-sandbox>/tests/uv/lock/requirements",
                stdout,
            )
            self.assertTrue(want_path.exists(), "The path should exist after the test")
            self.assertNotEqual(want_path.read_text(), "")

    def test_requirements_run_on_the_first_time(self):
        # Given
        copier_path = _relative_rpath("requirements_new_file.run")

        # When
        with tempfile.TemporaryDirectory() as dir:
            workspace_dir = Path(dir)
            want_path = workspace_dir / "tests" / "uv" / "lock" / "does_not_exist.txt"
            # NOTE @aignas 2025-03-18: right now we require users to have the folder
            # there already
            want_path.parent.mkdir(parents=True)

            self.assertFalse(
                want_path.exists(), "The path should not exist before the test"
            )
            output = _run_binary(
                copier_path,
                capture_output=True,
                env=self._subprocess_env(workspace_dir),
            )

            # Then
            self.assertEqual(0, output.returncode, output.stderr)
            self.assertTrue(want_path.exists(), "The path should exist after the test")
            got_contents = want_path.read_text()
            self.assertNotEqual(got_contents, "")
            # NOTE: stdout is typically empty because uv runs with --quiet --no-progress

    def test_requirements_run_script_has_expected_args(self):
        """Verify the .run script template has expected args embedded."""
        run_script_path = _relative_rpath("requirements.run")
        content = run_script_path.read_text()

        if os.name == "nt":
            self.assertIn("@echo off", content)
            self.assertIn("%*", content)
        else:
            self.assertIn("#!/usr/bin/env bash", content)
            self.assertIn('"$@"', content)
        self.assertIn("BUILD_WORKSPACE_DIRECTORY", content)
        self.assertIn("--custom-compile-command", content)
        self.assertIn("--generate-hashes", content)
        self.assertIn("--no-strip-extras", content)
        self.assertIn("--no-python-downloads", content)
        self.assertIn("--no-cache", content)
        self.assertIn("--no-progress", content)
        self.assertIn("--quiet", content)
        self.assertIn("--output-file", content)
        self.assertIn("requirements.txt", content)

    def test_requirements_run(self):
        # Given
        copier_path = _relative_rpath("requirements.run")

        # When
        with tempfile.TemporaryDirectory() as dir:
            workspace_dir = Path(dir)
            want_path = (
                workspace_dir
                / "tests"
                / "uv"
                / "lock"
                / "testdata"
                / "requirements.txt"
            )
            want_path.parent.mkdir(parents=True)

            output = _run_binary(
                copier_path,
                capture_output=True,
                env=self._subprocess_env(workspace_dir),
            )

            # Then
            self.assertEqual(0, output.returncode, output.stderr)
            self.assertTrue(want_path.exists(), "The path should exist after the test")
            got_contents = want_path.read_text()
            self.assertNotEqual(got_contents, "")
            # NOTE: stdout is typically empty because uv runs with --quiet --no-progress


if __name__ == "__main__":
    unittest.main()
