import importlib.metadata
import unittest


class ImportlibMetadataTest(unittest.TestCase):
    def _assert_distribution_files(self, dist_name, expected_files):
        files = importlib.metadata.files(dist_name)
        self.assertIsNotNone(
            files, f"importlib.metadata.files({dist_name!r}) returned None"
        )
        self.assertGreater(
            len(files),
            0,
            f"importlib.metadata.files({dist_name!r}) returned empty list",
        )

        posix_paths = [str(f).replace("\\", "/") for f in files]
        file_names = [f.name for f in files]

        for expected in expected_files:
            self.assertTrue(
                expected in posix_paths or expected in file_names,
                f"Expected {expected!r} to be in distribution files: {posix_paths}",
            )

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
            binary_content = f.read_binary()
            self.assertIsInstance(binary_content, bytes)

            text_content = f.read_text(encoding="utf-8")
            self.assertIsInstance(text_content, str)

    def test_whl_with_data1_files(self):
        self._assert_distribution_files(
            "whl-with-data1",
            [
                "data_overlap.py",
                "whl_with_data1/__init__.py",
                "whl_with_data1/data_file.txt",
                "whl_with_data1/platlib_file.txt",
                "whl_with_data1-1.0.dist-info/METADATA",
                "whl_with_data1-1.0.dist-info/WHEEL",
                "whl_with_data1-1.0.dist-info/RECORD",
            ],
        )

    def test_whl_with_data2_files(self):
        self._assert_distribution_files(
            "whl-with-data2",
            [
                "whl_with_data2/__init__.py",
                "whl_with_data2/data_file.txt",
                "whl_with_data2/platlib_file.txt",
                "whl_with_data2-1.0.dist-info/METADATA",
                "whl_with_data2-1.0.dist-info/WHEEL",
                "whl_with_data2-1.0.dist-info/RECORD",
                "whl_with_data2-1.0.dist-info/entry_points.txt",
            ],
        )


if __name__ == "__main__":
    unittest.main()
