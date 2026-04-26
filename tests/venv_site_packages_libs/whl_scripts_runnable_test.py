import subprocess
import sys
import unittest
from pathlib import Path


class WhlScriptsRunnableTest(unittest.TestCase):
    def test_script_is_runnable(self):
        is_windows = sys.platform == "win32"
        if is_windows:
            bin_dir = Path(sys.prefix) / "Scripts"
            # On windows, it might have .exe or no extension depending on how it was installed
            script_path = bin_dir / "whl_with_data1_script.exe"
            if not script_path.exists():
                script_path = bin_dir / "whl_with_data1_script"
        else:
            bin_dir = Path(sys.prefix) / "bin"
            script_path = bin_dir / "whl_with_data1_script"

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


if __name__ == "__main__":
    unittest.main()
