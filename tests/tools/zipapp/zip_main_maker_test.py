import hashlib
import os
import tempfile
import unittest
from unittest import mock

from tools.private.zipapp import zip_main_maker


class ZipMainMakerTest(unittest.TestCase):
    def setUp(self):
        self.temp_dir = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp_dir.cleanup)

    def test_creates_zip_main(self):
        template_path = os.path.join(self.temp_dir.name, "template.py")
        with open(template_path, "w", encoding="utf-8") as f:
            f.write("hash=%APP_HASH%\nfoo=%FOO%\n")

        output_path = os.path.join(self.temp_dir.name, "output.py")

        file1_path = os.path.join(self.temp_dir.name, "file1.txt")
        with open(file1_path, "wb") as f:
            f.write(b"content1")

        file2_path = os.path.join(self.temp_dir.name, "file2.txt")
        with open(file2_path, "wb") as f:
            f.write(b"content2")

        manifest_path = os.path.join(self.temp_dir.name, "manifest.txt")
        with open(manifest_path, "w", encoding="utf-8") as f:
            f.write(f"file1.txt|{file1_path}\n")
            f.write(f"file2.txt|{file2_path}\n")
            f.write(f"empty_file.txt\n")

        argv = [
            "zip_main_maker.py",
            "--template",
            template_path,
            "--output",
            output_path,
            "--substitution",
            "%FOO%=bar",
            "--hash_files_manifest",
            manifest_path,
        ]

        with mock.patch("sys.argv", argv):
            zip_main_maker.main()

        # Calculate expected hash
        h = hashlib.sha256()
        line1 = f"file1.txt|{file1_path}"
        line2 = f"file2.txt|{file2_path}"
        line3 = f"empty_file.txt"

        # Sort lines like the program does
        lines = sorted([line1, line2, line3])
        for line in lines:
            h.update(line.encode("utf-8"))
            parts = line.split("|")
            if len(parts) == 2:
                path = parts[1]
                with open(path, "rb") as f:
                    h.update(f.read())

        expected_hash = h.hexdigest()

        with open(output_path, "r", encoding="utf-8") as f:
            content = f.read()

        self.assertEqual(content, f"hash={expected_hash}\nfoo=bar\n")


if __name__ == "__main__":
    unittest.main()
