import os
import subprocess
import sys
import unittest


class SystemPythonZipAppTest(unittest.TestCase):
    def test_zipapp_runnable(self):
        zipapp_path = os.environ["TEST_ZIPAPP"]
        environment = dict(os.environ)
        if os.name == "nt":
            # Supply the test runtime as the system interpreter for the ZIP.
            environment["PATH"] = (
                os.path.dirname(sys.executable)
                + os.pathsep
                + environment.get("PATH", "")
            )

        self.assertTrue(os.path.exists(zipapp_path))
        self.assertTrue(os.path.isfile(zipapp_path))

        try:
            output = (
                subprocess.check_output(
                    [zipapp_path], stderr=subprocess.STDOUT, env=environment
                )
                .decode("utf-8")
                .strip()
            )
        except subprocess.CalledProcessError as e:
            self.fail(
                "exit code: {}\n"
                " command: {}\n"
                "===== stdout/stderr start ==={}===== stdout/stderr end ====".format(
                    e.returncode, e.cmd, e.output.decode("utf-8")
                )
            )
        self.assertIn("Hello from zipapp", output)
        self.assertIn("dep:", output)


if __name__ == "__main__":
    unittest.main()
