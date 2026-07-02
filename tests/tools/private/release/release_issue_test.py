import unittest

from tools.private.release.release_issue import (
    format_metadata_line,
    parse_metadata_line,
)


class ReleaseIssueTest(unittest.TestCase):
    def test_parse_metadata_line_spaces(self):
        # Test with spaces around '='
        line = "- [ ] Tag Final | tag = 2.0.0 commit = abcdef12"
        expected = {
            "checked": False,
            "name": "Tag Final",
            "metadata": {"tag": "2.0.0", "commit": "abcdef12"},
            "original_line": line,
        }
        self.assertEqual(parse_metadata_line(line), expected)

        # Test with spaces after '='
        line = "- [ ] Tag Final | tag= 2.0.0 commit= abcdef12"
        expected = {
            "checked": False,
            "name": "Tag Final",
            "metadata": {"tag": "2.0.0", "commit": "abcdef12"},
            "original_line": line,
        }
        self.assertEqual(parse_metadata_line(line), expected)

        # Test with standard format (no spaces)
        line = "- [ ] Tag Final | tag=2.0.0 commit=abcdef12"
        expected = {
            "checked": False,
            "name": "Tag Final",
            "metadata": {"tag": "2.0.0", "commit": "abcdef12"},
            "original_line": line,
        }
        self.assertEqual(parse_metadata_line(line), expected)

        # Test with no metadata
        line = "- [ ] Tag Final"
        expected = {
            "checked": False,
            "name": "Tag Final",
            "metadata": {},
            "original_line": line,
        }
        self.assertEqual(parse_metadata_line(line), expected)

    def test_format_metadata_line(self):
        # Test with commit metadata (should have space)
        metadata = {"status": "done", "tag": "2.0.0", "commit": "abcdef12"}
        expected = "- [x] Tag Final | status=done tag=2.0.0 commit= abcdef12"
        self.assertEqual(format_metadata_line(True, "Tag Final", metadata), expected)

        # Test with other metadata (should not have space)
        metadata = {"status": "done", "pr": "#122"}
        expected = "- [x] Prepare Release | status=done pr=#122"
        self.assertEqual(
            format_metadata_line(True, "Prepare Release", metadata), expected
        )

        # Test with no metadata
        expected = "- [ ] Tag Final"
        self.assertEqual(format_metadata_line(False, "Tag Final", {}), expected)


if __name__ == "__main__":
    unittest.main()
