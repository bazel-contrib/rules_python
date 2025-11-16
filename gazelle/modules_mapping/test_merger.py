import pathlib
import unittest
import json
import tempfile

from merger import merge_modules_mappings


class MergerTest(unittest.TestCase):
    def test_merger(self):
        file1 = tempfile.NamedTemporaryFile("w")
        json.dump(
            {
                "_pytest": "pytest",
                "_pytest.__init__": "pytest",
                "_pytest._argcomplete": "pytest",
                "_pytest.config.argparsing": "pytest",
            },
            file1,
        )
        file1.flush()
        file2 = tempfile.NamedTemporaryFile("w")
        json.dump(
            {"django_types": "django_types"},
            file2,
        )
        file2.flush()
        output_file = tempfile.NamedTemporaryFile("r")

        merge_modules_mappings(
            [pathlib.Path(file1.name), pathlib.Path(file2.name)],
            pathlib.Path(output_file.name),
        )

        self.assertEqual(
            {
                "_pytest": "pytest",
                "_pytest.__init__": "pytest",
                "_pytest._argcomplete": "pytest",
                "_pytest.config.argparsing": "pytest",
                "django_types": "django_types",
            },
            json.load(output_file),
        )


if __name__ == "__main__":
    unittest.main()
