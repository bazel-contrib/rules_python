import importlib.metadata
import unittest


class ImportlibMetadataTest(unittest.TestCase):
    def test_importlib_metadata_files(self):
        files = importlib.metadata.files("whl-with-data1")
        self.assertIsNotNone(files, "importlib.metadata.files returned None")
        self.assertGreater(
            len(files), 0, "importlib.metadata.files returned empty list"
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
            content = f.read_binary()
            self.assertIsNotNone(content)

            text = f.read_text(encoding="utf-8")
            self.assertIsNotNone(text)


if __name__ == "__main__":
    unittest.main()
