import pathlib
import unittest
import json
import tempfile

from merger import merge_modules_mappings


class MergerTest(unittest.TestCase):
    def test_merger(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            d = pathlib.Path(tmpdir)
            path1 = d / "file1.json"
            path2 = d / "file2.json"
            output_path = d / "output.json"

            path1.write_text(
                json.dumps(
                    {
                        "_pytest": "pytest",
                        "_pytest.__init__": "pytest",
                        "_pytest._argcomplete": "pytest",
                        "_pytest.config.argparsing": "pytest",
                    }
                )
            )

            path2.write_text(json.dumps({"django_types": "django_types"}))

            merge_modules_mappings([path1, path2], output_path)

            self.assertEqual(
                {
                    "_pytest": "pytest",
                    "_pytest.__init__": "pytest",
                    "_pytest._argcomplete": "pytest",
                    "_pytest.config.argparsing": "pytest",
                    "django_types": "django_types",
                },
                json.loads(output_path.read_text()),
            )


if __name__ == "__main__":
    unittest.main()
