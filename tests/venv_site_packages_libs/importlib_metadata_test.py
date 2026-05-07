import importlib.metadata
import unittest


class ImportlibMetadataTest(unittest.TestCase):

    def test_importlib_metadata_files(self):
        files = importlib.metadata.files("whl-with-data1")
        self.assertIsNotNone(files, "importlib.metadata.files returned None")
        self.assertGreater(
            len(files), 0, "importlib.metadata.files returned empty list"
        )

        # Verify it contains some expected files.
        # The RECORD file lists paths relative to the installation root (site-packages).
        # whl_with_data1-1.0.data/purelib/data_overlap.py should be installed as data_overlap.py
        # whl_with_data1-1.0.data/platlib/whl_with_data1/platlib_file.txt should be whl_with_data1/platlib_file.txt

        file_names = [f.name for f in files]
        self.assertIn("data_overlap.py", file_names)


if __name__ == "__main__":
    unittest.main()
