import importlib.metadata
import unittest


class ImportlibMetadataTest(unittest.TestCase):
    def test_importlib_metadata_files(self):
        files = importlib.metadata.files("whl-with-data1")
        self.assertIsNotNone(files, "importlib.metadata.files returned None")
        self.assertGreater(
            len(files), 0, "importlib.metadata.files returned empty list"
        )

        expected_paths = [
            "whl_with_data1-1.0.data/platlib/whl_with_data1/platlib_file.txt",
            "whl_with_data1-1.0.data/scripts/whl_with_data1_script",
            "whl_with_data1-1.0.data/scripts/whl_script.sh",
            "whl_with_data1-1.0.data/headers/whl_with_data1/header_file.h",
            "whl_with_data1-1.0.data/purelib/whl_with_data1/data_file.txt",
            "whl_with_data1-1.0.data/data/whl_with_data1/data_data_file.txt",
            "whl_with_data1-1.0.data/data/whl_with_data1/data_data_file.txt",
            "whl_with_data1-1.0.data/data/overlap/both.txt",
            "whl_with_data1-1.0.data/data/overlap/data1.txt",
            "whl_with_data1-1.0.data/scripts/overlap/both.sh",
            "whl_with_data1-1.0.data/scripts/overlap/script1.sh",
            "whl_with_data1-1.0.data/headers/overlap/both.h",
            "whl_with_data1-1.0.data/headers/overlap/header1.h",
            "whl_with_data1-1.0.data/scripts/data_overlap.sh",
            "whl_with_data1-1.0.data/data/bin/data_overlap.sh",
            "whl_with_data1-1.0.data/headers/data_overlap.h",
            "whl_with_data1-1.0.data/data/include/data_overlap.h",
            "whl_with_data1-1.0.data/purelib/data_overlap.py",
            "whl_with_data1-1.0.data/data/site-packages/data_overlap.py",
        ]
        file_paths = [str(f).replace("\\", "/") for f in files]
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
