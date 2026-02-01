import os
import subprocess
import unittest
import zipfile


class SystemPythonZipAppTest(unittest.TestCase):
    def test_zipapp_contents(self):
        zipapp_path = os.environ["TEST_ZIPAPP"]

        self.assertTrue(os.path.exists(zipapp_path))
        self.assertTrue(os.path.isfile(zipapp_path))

        # The zipapp itself is a shell script prepended to the zip file.
        with open(zipapp_path, "rb") as f:
            content = f.read()
        self.assertTrue(content.startswith(b"#!/usr/bin/env bash"))

        output = subprocess.check_output([zipapp_path]).decode("utf-8").strip()
        self.assertIn("Hello from zipapp", output)
        self.assertIn("absl", output)


if __name__ == "__main__":
    unittest.main()
