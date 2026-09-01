import sys
import unittest

import ext_long_path  # pyrefly: ignore[missing-import]


class PyExtensionLongPathTest(unittest.TestCase):
    def test_extension_is_loaded_from_extended_length_path(self):
        self.assertEqual(ext_long_path.get_magic_number(), 42)
        self.assertGreaterEqual(len(ext_long_path.__file__), 260)
        self.assertTrue(ext_long_path.__file__.startswith("\\\\?\\"))

    def test_other_python_paths_are_not_extended_length_paths(self):
        self.assertFalse(sys.prefix.startswith("\\\\?\\"))
        self.assertFalse(
            any(path.startswith("\\\\?\\") for path in sys.path),
            sys.path,
        )


if __name__ == "__main__":
    unittest.main()
