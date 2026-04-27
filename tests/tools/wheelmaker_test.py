import io
import unittest
from dataclasses import dataclass, field

import tools.wheelmaker as wheelmaker


class QuoteAllFilenamesTest(unittest.TestCase):
    """Tests for quote_all_filenames behavior in _WhlFile.

    Some wheels (like torch) have all filenames quoted in their RECORD file.
    When repacking, we preserve this style to minimize diffs.
    """

    def _make_whl_file(self, quote_all: bool) -> wheelmaker._WhlFile:
        """Create a _WhlFile instance for testing."""
        buf = io.BytesIO()
        return wheelmaker._WhlFile(
            buf,
            mode="w",
            distribution_prefix="test-1.0.0",
            quote_all_filenames=quote_all,
        )

    def test_quote_all_quotes_simple_filenames(self) -> None:
        """When quote_all_filenames=True, all filenames are quoted."""
        whl = self._make_whl_file(quote_all=True)
        self.assertEqual(whl._quote_filename("foo/bar.py"), '"foo/bar.py"')

    def test_quote_all_false_leaves_simple_filenames_unquoted(self) -> None:
        """When quote_all_filenames=False, simple filenames stay unquoted."""
        whl = self._make_whl_file(quote_all=False)
        self.assertEqual(whl._quote_filename("foo/bar.py"), "foo/bar.py")

    def test_quote_all_quotes_filenames_with_commas(self) -> None:
        """Filenames with commas are always quoted, regardless of quote_all_filenames."""
        whl = self._make_whl_file(quote_all=True)
        self.assertEqual(
            whl._quote_filename("foo,bar/baz.py"), '"foo,bar/baz.py"'
        )

        whl = self._make_whl_file(quote_all=False)
        self.assertEqual(
            whl._quote_filename("foo,bar/baz.py"), '"foo,bar/baz.py"'
        )


@dataclass
class ArcNameTestCase:
    name: str
    expected: str
    distribution_prefix: str = ""
    strip_path_prefixes: list[str] = field(default_factory=list)
    add_path_prefix: str = ""


class ArcNameFromTest(unittest.TestCase):
    def test_arcname_from(self) -> None:
        test_cases = [
            ArcNameTestCase(name="a/b/c/file.py", expected="a/b/c/file.py"),
            ArcNameTestCase(
                name="a/b/c/file.py",
                strip_path_prefixes=["a"],
                expected="/b/c/file.py",
            ),
            ArcNameTestCase(
                name="a/b/c/file.py",
                strip_path_prefixes=["a/b/"],
                expected="c/file.py",
            ),
            # only first found is used and it's not cumulative.
            ArcNameTestCase(
                name="a/b/c/file.py",
                strip_path_prefixes=["a/", "b/"],
                expected="b/c/file.py",
            ),
            # Examples from docs
            ArcNameTestCase(
                name="foo/bar/baz/file.py",
                strip_path_prefixes=["foo", "foo/bar/baz"],
                expected="/bar/baz/file.py",
            ),
            ArcNameTestCase(
                name="foo/bar/baz/file.py",
                strip_path_prefixes=["foo/bar/baz", "foo"],
                expected="/file.py",
            ),
            ArcNameTestCase(
                name="foo/file2.py",
                strip_path_prefixes=["foo/bar/baz", "foo"],
                expected="/file2.py",
            ),
            # Files under the distribution prefix (eg mylib-1.0.0-dist-info)
            # are unmodified
            ArcNameTestCase(
                name="mylib-0.0.1-dist-info/WHEEL",
                distribution_prefix="mylib",
                expected="mylib-0.0.1-dist-info/WHEEL",
            ),
            ArcNameTestCase(
                name="mylib/a/b/c/WHEEL",
                distribution_prefix="mylib",
                strip_path_prefixes=["mylib"],
                expected="mylib/a/b/c/WHEEL",
            ),
            # Check that prefixes are added
            ArcNameTestCase(
                name="a/b/c/file.py",
                add_path_prefix="namespace/",
                expected="namespace/a/b/c/file.py",
            ),
            ArcNameTestCase(
                name="a/b/c/file.py",
                strip_path_prefixes=["a"],
                add_path_prefix="namespace",
                expected="namespace/b/c/file.py",
            ),
            ArcNameTestCase(
                name="a/b/c/file.py",
                strip_path_prefixes=["a/b/"],
                add_path_prefix="namespace_",
                expected="namespace_c/file.py",
            ),
        ]
        for test_case in test_cases:
            with self.subTest(
                name=test_case.name,
                distribution_prefix=test_case.distribution_prefix,
                strip_path_prefixes=test_case.strip_path_prefixes,
                add_path_prefix=test_case.add_path_prefix,
                want=test_case.expected,
            ):
                got = wheelmaker.arcname_from(
                    name=test_case.name,
                    distribution_prefix=test_case.distribution_prefix,
                    strip_path_prefixes=test_case.strip_path_prefixes,
                    add_path_prefix=test_case.add_path_prefix,
                )
                self.assertEqual(got, test_case.expected)


class GetNewRequirementLineTest(unittest.TestCase):
    def test_requirement(self):
        result = wheelmaker.get_new_requirement_line("requests>=2.0", "")
        self.assertEqual(result, "Requires-Dist: requests>=2.0")

    def test_requirement_and_extra(self):
        result = wheelmaker.get_new_requirement_line(
            "requests>=2.0", "extra=='dev'"
        )
        self.assertEqual(result, "Requires-Dist: requests>=2.0; extra=='dev'")

    def test_requirement_with_url(self):
        result = wheelmaker.get_new_requirement_line(
            "requests @ git+https://github.com/psf/requests.git@3aa6386c3", ""
        )
        self.assertEqual(
            result,
            "Requires-Dist: requests @ git+https://github.com/psf/requests.git@3aa6386c3",
        )

    def test_requirement_with_marker(self):
        result = wheelmaker.get_new_requirement_line(
            "requests>=2.0; python_version>='3.6'", ""
        )
        self.assertEqual(
            result, 'Requires-Dist: requests>=2.0; python_version >= "3.6"'
        )

    def test_requirement_with_marker_and_extra(self):
        result = wheelmaker.get_new_requirement_line(
            "requests>=2.0; python_version>='3.6'", "extra=='dev'"
        )
        self.assertEqual(
            result,
            "Requires-Dist: requests>=2.0; (python_version >= \"3.6\") and extra=='dev'",
        )


if __name__ == "__main__":
    unittest.main()
