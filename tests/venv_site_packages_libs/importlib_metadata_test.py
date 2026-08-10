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

        if sys.platform == "win32":
            bin_prefix = "../../Scripts/"
            include_prefix = "../../Include/"
            data_prefix = "../../"
        else:
            bin_prefix = "../../../bin/"
            include_prefix = "../../../include/"
            data_prefix = "../../../"

        expected_paths = sorted(
            [
                bin_prefix + "data_overlap.sh",
                bin_prefix + "data_overlap.sh",
                bin_prefix + "overlap/both.sh",
                bin_prefix + "overlap/script1.sh",
                bin_prefix + "whl_script.sh",
                bin_prefix + "whl_with_data1_script",
                include_prefix + "data_overlap.h",
                include_prefix + "data_overlap.h",
                include_prefix + "overlap/both.h",
                include_prefix + "overlap/header1.h",
                include_prefix + "whl_with_data1/header_file.h",
                data_prefix + "overlap/both.txt",
                data_prefix + "overlap/data1.txt",
                data_prefix + "site-packages/data_overlap.py",
                data_prefix + "whl_with_data1/data_data_file.txt",
                data_prefix + "whl_with_data1/data_data_file.txt",
                "data_overlap.py",
                "whl_with_data1/data_file.txt",
                "whl_with_data1/platlib_file.txt",
            ]
        )
        file_paths = sorted(str(f).replace("\\", "/") for f in files)
        self.assertEqual(file_paths, expected_paths)

        for f in files:
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
