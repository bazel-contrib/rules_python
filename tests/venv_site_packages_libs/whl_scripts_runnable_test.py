import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

BAZEL_8_OR_LATER = bool(int(os.environ.get("BAZEL_8_OR_LATER", "0")))


class WhlScriptsRunnableTest(unittest.TestCase):
    maxDiff = None

    def _get_script_path(self, name):
        is_windows = sys.platform == "win32"
        if is_windows:
            bin_dir = Path(sys.prefix) / "Scripts"
            pathexts = os.environ.get("PATHEXT", ".COM;.EXE;.BAT;.CMD").split(";")
            for ext in [""] + [e.lower() for e in pathexts]:
                script_path = bin_dir / f"{name}{ext}"
                if script_path.exists():
                    return script_path
            return bin_dir / name
        else:
            bin_dir = Path(sys.prefix) / "bin"
            script_path = bin_dir / name
        return script_path

    def test_script_is_runnable(self):
        script_path = self._get_script_path("whl_with_data1_script")
        self.assertTrue(script_path.exists(), f"Script not found at {script_path}")

        result = subprocess.run(
            [str(script_path)],
            capture_output=True,
            text=True,
            check=True,
        )

        output = result.stdout.splitlines()
        self.assertIn("hello from whl_with_data1_script", output)

        # The script prints sys.executable as its second line
        # Depending on how it's invoked, it might have more output,
        # but the user said it prints the hello message AND sys.executable.
        script_executable = output[-1].strip()
        self.assertEqual(script_executable, sys.executable)

    def test_entry_point_is_runnable(self):
        script_path = self._get_script_path("whl_with_data2_bin")
        self.assertTrue(script_path.exists(), f"Entry point not found at {script_path}")

        result = subprocess.run(
            [str(script_path)],
            capture_output=True,
            text=True,
            check=True,
        )

        output = result.stdout.splitlines()
        self.assertIn("hello from whl_with_data2_bin", output)

        script_executable = output[-1].strip()
        self.assertEqual(script_executable, sys.executable)

    def test_pythonw_script(self):
        script_path = self._get_script_path("whl_with_data1_pythonw")
        self.assertTrue(script_path.exists(), f"Script not found at {script_path}")

        with open(script_path, "r", encoding="utf-8") as f:
            first_line = f.readline()

        is_windows = sys.platform == "win32"
        if is_windows:
            # On Windows, the shebang is replaced with a batch wrapper that
            # invokes the interpreter.
            self.assertIn("pythonw.exe", first_line)
            self.assertTrue(
                first_line.startswith("@setlocal")
                or first_line.startswith("@echo off"),
                f"Expected Windows batch wrapper, got {first_line}",
            )
        else:
            self.assertTrue(
                first_line.startswith("#!/bin/sh"),
                f"Expected #!/bin/sh, got {first_line}",
            )

        # For some reason, on Windows, the subprocess can't write
        # to the temporary files unless mkstemp is used.
        temp_fd, temp_str = tempfile.mkstemp()
        try:
            os.close(temp_fd)
            out_path = Path(temp_str)
            result = subprocess.run(
                [str(script_path), str(out_path)],
                capture_output=True,
                text=True,
                check=True,
            )
            output = out_path.read_text().splitlines()
        finally:
            os.unlink(temp_str)
        self.assertIn("hello from whl_with_data1_pythonw", output)

        script_executable = output[-1].strip()

        if is_windows:
            self.assertTrue(
                script_executable.endswith("pythonw.exe"),
                f"Expected pythonw.exe, got {script_executable}",
            )


if __name__ == "__main__":
    unittest.main()
