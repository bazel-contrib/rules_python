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

        # Add a symlink to test symlink hashing
        symlink_path = os.path.join(self.temp_dir.name, "symlink.txt")
        os.symlink(file1_path, symlink_path)

        manifest_path = os.path.join(self.temp_dir.name, "manifest.txt")
        with open(manifest_path, "w", encoding="utf-8") as f:
            f.write(f"rf-file|0|file1.txt|{file1_path}\n")
            f.write(f"rf-file|0|file2.txt|{file2_path}\n")
            f.write(f"rf-symlink|1|symlink.txt|{symlink_path}\n")
            f.write(f"rf-empty|empty_file.txt\n")

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
        line1 = f"rf-file|0|file1.txt|{file1_path}"
        line2 = f"rf-file|0|file2.txt|{file2_path}"
        line3 = f"rf-symlink|1|symlink.txt|{symlink_path}"
        line4 = f"rf-empty|empty_file.txt"

        # Sort lines like the program does
        lines = sorted([line1, line2, line3, line4])
        for line in lines:
            parts = line.split("|")
            if len(parts) > 1:
                _, rest = line.split("|", 1)
                h.update(rest.encode("utf-8"))
            else:
                h.update(line.encode("utf-8"))

            type_ = parts[0]
            if type_ == "rf-empty":
                continue
            if len(parts) >= 4:
                is_symlink_str = parts[1]
                path = parts[-1]
                if not path:
                    continue
                if is_symlink_str == "-1":
                    is_symlink = not os.path.exists(path)
                else:
                    is_symlink = is_symlink_str == "1"

                if is_symlink:
                    h.update(os.readlink(path).encode("utf-8"))
                else:
                    with open(path, "rb") as f:
                        h.update(f.read())

        expected_hash = h.hexdigest()

        with open(output_path, "r", encoding="utf-8") as f:
            content = f.read()

        self.assertEqual(content, f"hash={expected_hash}\nfoo=bar\n")


if __name__ == "__main__":
    unittest.main()
