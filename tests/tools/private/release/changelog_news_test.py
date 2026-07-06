import pathlib
import unittest
from unittest.mock import patch

from tests.tools.private.release.release_test_helper import TempDirTestCase
from tools.private.release import changelog_news


class ChangelogNewsTest(TempDirTestCase):
    def test_update_changelog_with_news(self):
        # Arrange
        changelog = """# Changelog

{#unreleased}
## Unreleased

[unreleased]: https://github.com/bazel-contrib/rules_python/releases/tag/unreleased

Unreleased changes are tracked as individual files in the [news/](./news)
directory, or view the [latest generated
changelog](https://rules-python.readthedocs.io/en/latest/changelog.html).

{#v2-0-2}
## [2.0.2] - 2026-05-14

[2.0.2]: https://github.com/bazel-contrib/rules_python/releases/tag/2.0.2

{#v2-0-2-added}
### Added
* (toolchains) Some older change.
"""
        changelog_path = self.tmpdir / "CHANGELOG.md"
        changelog_path.write_text(changelog)

        news_dir = self.tmpdir / "news"
        news_dir.mkdir()

        # Create news files
        (news_dir / "123.fixed.md").write_text("Fixed a bug in the compiler")
        # Test that it handles prefixing "* " if not present
        (news_dir / "456.added.md").write_text("* Added a new feature for Python 3.13")
        # Empty file should be ignored
        (news_dir / "789.changed.md").write_text("")
        # Invalid name should be ignored
        (news_dir / "invalid_name.md").write_text("Should be ignored")

        # Act
        changelog_news.update_changelog(
            "3.0.0",
            "2026-06-16",
            changelog_path=changelog_path,
            news_dir=news_dir,
        )

        # Assert
        # 1. News files matching the pattern should be deleted (even empty ones)
        self.assertFalse((news_dir / "123.fixed.md").exists())
        self.assertFalse((news_dir / "456.added.md").exists())
        self.assertFalse((news_dir / "789.changed.md").exists())
        # Invalid name does not match pattern -> NOT deleted
        self.assertTrue((news_dir / "invalid_name.md").exists())

        new_content = changelog_path.read_text()

        # 2. A fresh active Unreleased section should be present
        self.assertIn("{#unreleased}", new_content)
        self.assertIn("## Unreleased", new_content)
        self.assertIn(
            "Unreleased changes are tracked as individual files in the [news/](./news)\n"
            "directory, or view the [latest generated\n"
            "changelog](https://rules-python.readthedocs.io/en/latest/changelog.html).",
            new_content,
        )

        # 3. The new release section should be present
        self.assertIn("{#v3-0-0}", new_content)
        self.assertIn("## [3.0.0] - 2026-06-16", new_content)
        self.assertIn(
            "[3.0.0]: https://github.com/bazel-contrib/rules_python/releases/tag/3.0.0",
            new_content,
        )

        # 4. Correct categories and content
        self.assertIn(
            "{#v3-0-0-fixed}\n### Fixed\n* Fixed a bug in the compiler",
            new_content,
        )
        self.assertIn(
            "{#v3-0-0-added}\n### Added\n* Added a new feature for Python 3.13",
            new_content,
        )

        # 5. Omitted categories should NOT be present in the new release
        self.assertNotIn("{#v3-0-0-removed}", new_content)
        self.assertNotIn("{#v3-0-0-changed}", new_content)

        # 6. Old release should still be there
        self.assertIn("{#v2-0-2}", new_content)
        self.assertIn("## [2.0.2] - 2026-05-14", new_content)

    def test_update_changelog_sorting(self):
        # Arrange
        changelog = """# Changelog

{#unreleased}
## Unreleased

[unreleased]: https://github.com/bazel-contrib/rules_python/releases/tag/unreleased

Unreleased changes are tracked as individual files in the [news/](./news)
directory, or view the [latest generated
changelog](https://rules-python.readthedocs.io/en/latest/changelog.html).

{#v2-0-2}
## [2.0.2] - 2026-05-14

[2.0.2]: https://github.com/bazel-contrib/rules_python/releases/tag/2.0.2

{#v2-0-2-added}
### Added
* (toolchains) Some older change.
"""
        changelog_path = self.tmpdir / "CHANGELOG.md"
        changelog_path.write_text(changelog)

        news_dir = self.tmpdir / "news"
        news_dir.mkdir()

        # Create news files with different sub-categories and some without
        (news_dir / "1.fixed.md").write_text("* (zebra) Zebra fix")
        (news_dir / "2.fixed.md").write_text("* (apple) Apple fix")
        (news_dir / "3.fixed.md").write_text("No subcategory B")
        (news_dir / "4.fixed.md").write_text("* (apple) Another apple fix")
        (news_dir / "5.fixed.md").write_text("No subcategory A")

        # Act
        changelog_news.update_changelog(
            "3.0.0",
            "2026-06-16",
            changelog_path=changelog_path,
            news_dir=news_dir,
        )

        # Assert
        new_content = changelog_path.read_text()

        # Expected order in Fixed section:
        # 1. No subcategory A
        # 2. No subcategory B
        # 3. (apple) Another apple fix
        # 4. (apple) Apple fix
        # 5. (zebra) Zebra fix

        expected_fixed_section = (
            "### Fixed\n"
            "* No subcategory A\n"
            "* No subcategory B\n"
            "* (apple) Another apple fix\n"
            "* (apple) Apple fix\n"
            "* (zebra) Zebra fix\n"
        )

        self.assertIn(expected_fixed_section, new_content)

    def test_update_changelog_read_failure(self):
        # Arrange
        original_read_text = pathlib.Path.read_text

        with patch("pathlib.Path.read_text", autospec=True) as mock_read_text:

            def side_effect(path_self, *args, **kwargs):
                if "bad_file.fixed.md" in str(path_self):
                    raise IOError("Simulated read error")
                return original_read_text(path_self, *args, **kwargs)

            mock_read_text.side_effect = side_effect

            changelog = """# Changelog

{#unreleased}
## Unreleased

[unreleased]: https://github.com/bazel-contrib/rules_python/releases/tag/unreleased

Unreleased changes are tracked as individual files in the [news/](./news)
directory, or view the [latest generated
changelog](https://rules-python.readthedocs.io/en/latest/changelog.html).

{#v2-0-2}
## [2.0.2] - 2026-05-14

[2.0.2]: https://github.com/bazel-contrib/rules_python/releases/tag/2.0.2

{#v2-0-2-added}
### Added
* (toolchains) Some older change.
"""
            changelog_path = self.tmpdir / "CHANGELOG.md"
            changelog_path.write_text(changelog)

            news_dir = self.tmpdir / "news"
            news_dir.mkdir()

            # Create the bad file (must exist so it is found by iterdir)
            bad_file = news_dir / "bad_file.fixed.md"
            bad_file.write_text("some content that won't be read")

            # Create a good file too
            good_file = news_dir / "good_file.fixed.md"
            good_file.write_text("* (sub) Good fix")

            # Act & Assert
            # It should raise IOError
            with self.assertRaises(IOError):
                changelog_news.update_changelog(
                    "3.0.0",
                    "2026-06-16",
                    changelog_path=changelog_path,
                    news_dir=news_dir,
                )

            # Both files should still exist (no deletion on failure!)
            self.assertTrue(bad_file.exists())
            self.assertTrue(good_file.exists())

            # Changelog should not be modified
            new_content = changelog_path.read_text()
            self.assertEqual(changelog, new_content)

    def test_update_changelog_merge_existing(self):
        # Arrange
        changelog = """# Changelog

{#unreleased}
## Unreleased

[unreleased]: https://github.com/bazel-contrib/rules_python/releases/tag/unreleased

Unreleased changes are tracked as individual files in the [news/](./news)
directory, or view the [latest generated
changelog](https://rules-python.readthedocs.io/en/latest/changelog.html).

{#v2-0-3}
## [2.0.3] - 2026-06-15

[2.0.3]: https://github.com/bazel-contrib/rules_python/releases/tag/2.0.3

{#v2-0-3-fixed}
### Fixed
* (pypi) Old fix
  multi-line detail
  * nested bullet item
* (pypi) Z old fix
"""
        changelog_path = self.tmpdir / "CHANGELOG.md"
        changelog_path.write_text(changelog)

        news_dir = self.tmpdir / "news"
        news_dir.mkdir()

        # Create news files to merge
        # 1. New fix in same category (should merge and sort)
        (news_dir / "1.fixed.md").write_text("(pypi) New fix")
        # 2. New entry in new category (should create category)
        (news_dir / "2.added.md").write_text("(toolchains) New feature")

        # Act
        changelog_news.update_changelog(
            "2.0.3",
            "2026-06-15",
            changelog_path=changelog_path,
            news_dir=news_dir,
        )

        # Assert
        # News files should be deleted
        self.assertFalse((news_dir / "1.fixed.md").exists())
        self.assertFalse((news_dir / "2.added.md").exists())

        new_content = changelog_path.read_text()

        # Expected merged and sorted Fixed section:
        # 1. (pypi) New fix (New < Old)
        # 2. (pypi) Old fix (with its multi-line detail!)
        # 3. (pypi) Z old fix
        expected_fixed_section = (
            "### Fixed\n"
            "* (pypi) New fix\n"
            "* (pypi) Old fix\n"
            "  multi-line detail\n"
            "  * nested bullet item\n"
            "* (pypi) Z old fix\n"
        )
        self.assertIn(expected_fixed_section, new_content)

        # Expected created Added section:
        expected_added_section = "### Added\n* (toolchains) New feature\n"
        self.assertIn(expected_added_section, new_content)

        # Active Unreleased section should NOT be touched (should still be empty/pointing to news)
        self.assertIn("Unreleased changes are tracked as individual files", new_content)

    def test_update_changelog_does_not_leak(self):
        # Arrange
        changelog = """# Changelog

{#unreleased}
## Unreleased

[unreleased]: https://github.com/bazel-contrib/rules_python/releases/tag/unreleased

Unreleased changes are tracked as individual files in the [news/](./news)
directory, or view the [latest generated
changelog](https://rules-python.readthedocs.io/en/latest/changelog.html).

{#v2-0-2}
## [2.0.2] - 2026-05-14

[2.0.2]: https://github.com/bazel-contrib/rules_python/releases/tag/2.0.2

This release body mentions the word unreleased and {#unreleased} anchor to test leaks.
"""
        changelog_path = self.tmpdir / "CHANGELOG.md"
        changelog_path.write_text(changelog)

        news_dir = self.tmpdir / "news"
        news_dir.mkdir()
        (news_dir / "1.fixed.md").write_text("Some fix")

        # Act
        changelog_news.update_changelog(
            "3.0.0",
            "2026-06-16",
            changelog_path=changelog_path,
            news_dir=news_dir,
        )

        # Assert
        new_content = changelog_path.read_text()

        # The 2.0.2 body should NOT be modified
        self.assertIn(
            "This release body mentions the word unreleased and {#unreleased} anchor to test leaks.",
            new_content,
        )

    def test_update_changelog_empty_news(self):
        # Arrange
        changelog = """# Changelog

{#unreleased}
## Unreleased

[unreleased]: https://github.com/bazel-contrib/rules_python/releases/tag/unreleased

Unreleased changes are tracked as individual files in the [news/](./news)
directory, or view the [latest generated
changelog](https://rules-python.readthedocs.io/en/latest/changelog.html).

{#v2-0-2}
## [2.0.2] - 2026-05-14

[2.0.2]: https://github.com/bazel-contrib/rules_python/releases/tag/2.0.2

{#v2-0-2-added}
### Added
* (toolchains) Some older change.
"""
        changelog_path = self.tmpdir / "CHANGELOG.md"
        changelog_path.write_text(changelog)

        news_dir = self.tmpdir / "news"
        news_dir.mkdir()

        # Act
        changelog_news.update_changelog(
            "3.0.0",
            "2026-06-16",
            changelog_path=changelog_path,
            news_dir=news_dir,
        )

        # Assert
        new_content = changelog_path.read_text()

        # The new release section should be present and contain "No notable changes."
        self.assertIn("{#v3-0-0}", new_content)
        self.assertIn("## [3.0.0] - 2026-06-16", new_content)
        self.assertIn(
            "[3.0.0]: https://github.com/bazel-contrib/rules_python/releases/tag/3.0.0",
            new_content,
        )
        self.assertIn("No notable changes.", new_content)

        # Verify that we didn't accidentally create any categories
        self.assertNotIn("{#v3-0-0-fixed}", new_content)
        self.assertNotIn("{#v3-0-0-added}", new_content)

    def test_update_changelog_selective_news_files(self):
        # Arrange
        changelog = """# Changelog

{#unreleased}
## Unreleased

[unreleased]: https://github.com/bazel-contrib/rules_python/releases/tag/unreleased

{#v2-0-2}
## [2.0.2] - 2026-05-14

[2.0.2]: https://github.com/bazel-contrib/rules_python/releases/tag/2.0.2
"""
        changelog_path = self.tmpdir / "CHANGELOG.md"
        changelog_path.write_text(changelog)

        news_dir = self.tmpdir / "news"
        news_dir.mkdir()

        # Create news files
        (news_dir / "123.fixed.md").write_text("Fix A")
        (news_dir / "456.fixed.md").write_text("Fix B")

        # Act: Only process 123.fixed.md
        changelog_news.update_changelog(
            "2.0.3",
            "2026-06-16",
            changelog_path=changelog_path,
            news_dir=news_dir,
            news_files=[news_dir / "123.fixed.md"],
        )

        # Assert
        # 1. Only 123.fixed.md should be deleted
        self.assertFalse((news_dir / "123.fixed.md").exists())
        self.assertTrue((news_dir / "456.fixed.md").exists())

        new_content = changelog_path.read_text()

        # 2. Only Fix A should be in the changelog
        self.assertIn("Fix A", new_content)
        self.assertNotIn("Fix B", new_content)

    def test_update_changelog_insertion_point(self):
        # Arrange
        changelog = """# Changelog

{#unreleased}
## Unreleased

[unreleased]: https://github.com/bazel-contrib/rules_python/releases/tag/unreleased

{#v2-2-0}
## [2.2.0] - 2026-06-30

[2.2.0]: https://github.com/bazel-contrib/rules_python/releases/tag/2.2.0

{#v2-0-0}
## [2.0.0] - 2026-04-09

[2.0.0]: https://github.com/bazel-contrib/rules_python/releases/tag/2.0.0
"""
        changelog_path = self.tmpdir / "CHANGELOG.md"
        changelog_path.write_text(changelog)

        news_dir = self.tmpdir / "news"
        news_dir.mkdir()
        (news_dir / "123.fixed.md").write_text("Fix in 2.1.0")

        # Act: Insert 2.1.0
        changelog_news.update_changelog(
            "2.1.0",
            "2026-06-17",
            changelog_path=changelog_path,
            news_dir=news_dir,
        )

        # Assert
        new_content = changelog_path.read_text()

        # Verify 2.1.0 is inserted BEFORE 2.0.0 but AFTER 2.2.0
        idx_2_2_0 = new_content.index("{#v2-2-0}")
        idx_2_1_0 = new_content.index("{#v2-1-0}")
        idx_2_0_0 = new_content.index("{#v2-0-0}")

        self.assertTrue(idx_2_2_0 < idx_2_1_0 < idx_2_0_0)
        self.assertIn("Fix in 2.1.0", new_content)

    def test_update_changelog_insertion_point_too_small(self):
        # Arrange
        changelog = """# Changelog

{#unreleased}
## Unreleased

[unreleased]: https://github.com/bazel-contrib/rules_python/releases/tag/unreleased

{#v2-0-0}
## [2.0.0] - 2026-04-09

[2.0.0]: https://github.com/bazel-contrib/rules_python/releases/tag/2.0.0
"""
        changelog_path = self.tmpdir / "CHANGELOG.md"
        changelog_path.write_text(changelog)

        news_dir = self.tmpdir / "news"
        news_dir.mkdir()
        (news_dir / "123.fixed.md").write_text("Fix in 1.0.0")

        # Act & Assert
        with self.assertRaises(ValueError) as ctx:
            changelog_news.update_changelog(
                "1.0.0",
                "2026-01-01",
                changelog_path=changelog_path,
                news_dir=news_dir,
            )
        self.assertIn(
            "Could not find a version in CHANGELOG.md smaller than 1.0.0",
            str(ctx.exception),
        )


if __name__ == "__main__":
    unittest.main()
