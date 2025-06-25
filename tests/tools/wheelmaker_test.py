import unittest

import tools.wheelmaker as wheelmaker


class ArcNameFromTest(unittest.TestCase):

    def test_arcname_from(self) -> None:

        # (name, distribution_prefix, strip_path_prefixes, want) tuples
        checks = [
            ("foo/bar/baz/file.py", "", [], "foo/bar/baz/file.py"),
            ("foo/bar/baz/file.py", "", ["foo"], "/bar/baz/file.py"),
            ("foo/bar/baz/file.py", "", ["foo/"], "bar/baz/file.py"),
            ("foo/bar/baz/file.py", "", ["foo/bar"], "/baz/file.py"),
            ("foo/bar/baz/file.py", "", ["foo/bar", "baz"], "/baz/file.py"),
            ("foo/bar/baz/file.py", "", ["foo", "bar"], "/bar/baz/file.py"),
            ("foo/bar/baz/file.py", "", ["baz", "foo/bar"], "/baz/file.py"),
        ]
        for name, prefix, strip, want in checks:
            with self.subTest(name=name, distribution_prefix=prefix, strip_path_prefixes=strip, want=want):
                got = wheelmaker.arcname_from(name=name, distribution_prefix=prefix, strip_path_prefixes=strip)
                self.assertEqual(got, want)


if __name__ == "__main__":
    unittest.main()
