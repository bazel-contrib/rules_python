import importlib.metadata
import sys
import unittest


class ImportlibMetadataTest(unittest.TestCase):
    def test_importlib_metadata_files(self):
        files = importlib.metadata.files("whl-with-data1")
        self.assertIsNotNone(files, "importlib.metadata.files returned None")
        self.assertGreater(
            len(files), 0, "importlib.metadata.files returned empty list"
        )

        expected_paths = [
            "../../../bin/data_overlap.sh",
            "../../../bin/data_overlap.sh",
            "../../../bin/overlap/both.sh",
            "../../../bin/overlap/script1.sh",
            "../../../bin/whl_script.sh",
            "../../../bin/whl_with_data1_script",
            "../../../include/data_overlap.h",
            "../../../include/data_overlap.h",
            "../../../include/overlap/both.h",
            "../../../include/overlap/header1.h",
            "../../../include/whl_with_data1/header_file.h",
            "../../../overlap/both.txt",
            "../../../overlap/data1.txt",
            "../../../site-packages/data_overlap.py",
            "../../../whl_with_data1/data_data_file.txt",
            "../../../whl_with_data1/data_data_file.txt",
            "data_overlap.py",
            "whl_with_data1/data_file.txt",
            "whl_with_data1/platlib_file.txt",
        ]
        file_paths = sorted(str(f).replace("\\", "/") for f in files)
        self.assertEqual(file_paths, expected_paths)

        is_windows = sys.platform == "win32"
        for f in files:
            # On Windows, virtual environments have a 2-level directory depth
            # (Lib/site-packages) while POSIX virtual environments have a
            # 3-level depth (lib/pythonX.Y/site-packages). Since wheel
            # extraction writes POSIX-standard relative paths (../../../) in
            # RECORD, files outside site-packages cannot be resolved via
            # locate() on Windows.
            if is_windows and str(f).startswith(".."):
                continue

            resolved = f.locate()
            self.assertTrue(
                resolved.exists(),
                f"Expected file {f} (resolved to {resolved}) to exist",
            )
            self.assertTrue(
                resolved.is_file(),
                f"Expected {resolved} to be a regular file",
            )

            # Verify file content can be read both as binary and as text
            content = f.read_binary()
            self.assertIsNotNone(content)

            text = f.read_text(encoding="utf-8")
            self.assertIsNotNone(text)


if __name__ == "__main__":
    unittest.main()
