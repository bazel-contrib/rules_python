import os
import pathlib
import shutil
import tempfile
import unittest
from unittest.mock import patch

from tools.private.release import changelog_news, release as releaser


class ReleaserTest(unittest.TestCase):
    def setUp(self):
        self.tmpdir = pathlib.Path(tempfile.mkdtemp())
        self.original_cwd = os.getcwd()
        self.addCleanup(shutil.rmtree, self.tmpdir)

        os.chdir(self.tmpdir)
        # NOTE: On windows, this must be done before files are deleted.
        self.addCleanup(os.chdir, self.original_cwd)

    def test_update_changelog_with_news(self):
        # Arrange
        changelog = """# Changelog

{#unreleased}
## Unreleased

[unreleased]: https://github.com/bazel-contrib/rules_python/releases/tag/unreleased

{#unreleased-removed}
### Removed
* Nothing removed.

{#unreleased-changed}
### Changed
* Nothing changed.

{#unreleased-fixed}
### Fixed
* Nothing fixed.

{#unreleased-added}
### Added
* Nothing added.

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
            "{#v3-0-0-fixed}\n### Fixed\n* Fixed a bug in the compiler", new_content
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

    def test_replace_version_next(self):
        # Arrange
        mock_file_content = """
:::{versionadded} VERSION_NEXT_FEATURE
blabla
:::

:::{versionchanged} VERSION_NEXT_PATCH
blabla
:::
"""
        (self.tmpdir / "mock_file.bzl").write_text(mock_file_content)

        releaser.replace_version_next("0.28.0")

        new_content = (self.tmpdir / "mock_file.bzl").read_text()

        self.assertIn(":::{versionadded} 0.28.0", new_content)
        self.assertIn(":::{versionadded} 0.28.0", new_content)
        self.assertNotIn("VERSION_NEXT_FEATURE", new_content)
        self.assertNotIn("VERSION_NEXT_PATCH", new_content)

    def test_replace_version_next_excludes_bazel_dirs(self):
        # Arrange
        mock_file_content = """
:::{versionadded} VERSION_NEXT_FEATURE
blabla
:::
"""
        bazel_dir = self.tmpdir / "bazel-rules_python"
        bazel_dir.mkdir()
        (bazel_dir / "mock_file.bzl").write_text(mock_file_content)

        tools_dir = self.tmpdir / "tools" / "private" / "release"
        tools_dir.mkdir(parents=True)
        (tools_dir / "mock_file.bzl").write_text(mock_file_content)

        tests_dir = self.tmpdir / "tests" / "tools" / "private" / "release"
        tests_dir.mkdir(parents=True)
        (tests_dir / "mock_file.bzl").write_text(mock_file_content)

        version = "0.28.0"

        # Act
        releaser.replace_version_next(version)

        # Assert
        new_content = (bazel_dir / "mock_file.bzl").read_text()
        self.assertIn("VERSION_NEXT_FEATURE", new_content)

        new_content = (tools_dir / "mock_file.bzl").read_text()
        self.assertIn("VERSION_NEXT_FEATURE", new_content)

        new_content = (tests_dir / "mock_file.bzl").read_text()
        self.assertIn("VERSION_NEXT_FEATURE", new_content)

    def test_valid_version(self):
        # These should not raise an exception
        releaser.create_parser().parse_args(["prepare", "0.28.0"])
        releaser.create_parser().parse_args(["promote-rc", "1.0.0"])
        releaser.create_parser().parse_args(
            ["create-release-issue", "--version", "1.2.3rc4"]
        )

    def test_invalid_version(self):
        with self.assertRaises(SystemExit):
            releaser.create_parser().parse_args(["prepare", "0.28"])
        with self.assertRaises(SystemExit):
            releaser.create_parser().parse_args(["prepare", "a.b.c"])


class GetLatestVersionTest(unittest.TestCase):
    @patch("tools.private.release.release.git.get_tags")
    def test_get_latest_version_success(self, mock_get_tags):
        mock_get_tags.return_value = ["0.1.0", "1.0.0", "0.2.0"]
        self.assertEqual(releaser.get_latest_version(), "1.0.0")

    @patch("tools.private.release.release.git.get_tags")
    def test_get_latest_version_rc_is_latest(self, mock_get_tags):
        mock_get_tags.return_value = ["0.1.0", "1.0.0", "1.1.0rc0"]
        with self.assertRaisesRegex(
            ValueError, "The latest version is a pre-release version: 1.1.0rc0"
        ):
            releaser.get_latest_version()

    @patch("tools.private.release.release.git.get_tags")
    def test_get_latest_version_no_tags(self, mock_get_tags):
        mock_get_tags.return_value = []
        with self.assertRaisesRegex(
            RuntimeError, "No git tags found matching X.Y.Z or X.Y.ZrcN format."
        ):
            releaser.get_latest_version()

    @patch("tools.private.release.release.git.get_tags")
    def test_get_latest_version_no_matching_tags(self, mock_get_tags):
        mock_get_tags.return_value = ["v1.0", "latest"]
        with self.assertRaisesRegex(
            RuntimeError, "No git tags found matching X.Y.Z or X.Y.ZrcN format."
        ):
            releaser.get_latest_version()

    @patch("tools.private.release.release.git.get_tags")
    def test_get_latest_version_only_rc_tags(self, mock_get_tags):
        mock_get_tags.return_value = ["1.0.0rc0", "1.1.0rc0"]
        with self.assertRaisesRegex(
            ValueError, "The latest version is a pre-release version: 1.1.0rc0"
        ):
            releaser.get_latest_version()


class DetermineNextVersionTest(unittest.TestCase):
    def setUp(self):
        self.tmpdir = pathlib.Path(tempfile.mkdtemp())
        self.original_cwd = os.getcwd()
        self.addCleanup(shutil.rmtree, self.tmpdir)

        os.chdir(self.tmpdir)
        # NOTE: On windows, this must be done before files are deleted.
        self.addCleanup(os.chdir, self.original_cwd)

        self.mock_get_latest_version = patch(
            "tools.private.release.release.get_latest_version"
        ).start()
        self.addCleanup(patch.stopall)

    def test_no_markers(self):
        (self.tmpdir / "mock_file.bzl").write_text("no markers here")
        self.mock_get_latest_version.return_value = "1.2.3"

        next_version = releaser.determine_next_version()

        self.assertEqual(next_version, "1.2.4")

    def test_only_patch(self):
        (self.tmpdir / "mock_file.bzl").write_text(
            ":::{versionchanged} VERSION_NEXT_PATCH"
        )
        self.mock_get_latest_version.return_value = "1.2.3"

        next_version = releaser.determine_next_version()

        self.assertEqual(next_version, "1.2.4")

    def test_only_feature(self):
        (self.tmpdir / "mock_file.bzl").write_text(
            ":::{versionadded} VERSION_NEXT_FEATURE"
        )
        self.mock_get_latest_version.return_value = "1.2.3"

        next_version = releaser.determine_next_version()

        self.assertEqual(next_version, "1.3.0")

    def test_both_markers(self):
        (self.tmpdir / "mock_file_patch.bzl").write_text(
            ":::{versionchanged} VERSION_NEXT_PATCH"
        )
        (self.tmpdir / "mock_file_feature.bzl").write_text(
            ":::{versionadded} VERSION_NEXT_FEATURE"
        )
        self.mock_get_latest_version.return_value = "1.2.3"

        next_version = releaser.determine_next_version()

        self.assertEqual(next_version, "1.3.0")

    @patch("tools.private.release.release.git.get_current_branch")
    @patch("tools.private.release.release.git.get_tags")
    def test_determine_next_version_on_release_branch_with_existing_tags(
        self, mock_get_tags, mock_get_branch
    ):
        mock_get_branch.return_value = "release/0.37"
        mock_get_tags.return_value = ["0.37.0", "0.37.1", "0.36.0"]

        next_version = releaser.determine_next_version()

        self.assertEqual(next_version, "0.37.2")

    @patch("tools.private.release.release.git.get_current_branch")
    @patch("tools.private.release.release.git.get_tags")
    def test_determine_next_version_on_release_branch_no_tags(
        self, mock_get_tags, mock_get_branch
    ):
        mock_get_branch.return_value = "release/0.38"
        mock_get_tags.return_value = ["0.37.0"]  # No 0.38.x tags

        next_version = releaser.determine_next_version()

        self.assertEqual(next_version, "0.38.0")

    @patch("tools.private.release.release.git.get_current_branch")
    @patch("tools.private.release.release.git.get_tags")
    def test_determine_next_version_on_release_branch_with_active_rc(
        self, mock_get_tags, mock_get_branch
    ):
        mock_get_branch.return_value = "release/0.37"
        # 0.37.0-rc0 and rc1 exist, but no stable 0.37.0 yet
        mock_get_tags.return_value = ["0.37.0-rc0", "0.37.0-rc1", "0.36.0"]

        next_version = releaser.determine_next_version()

        # Should target 0.37.0, not 0.37.1
        self.assertEqual(next_version, "0.37.0")

    @patch("tools.private.release.release.git.get_current_branch")
    @patch("tools.private.release.release.git.get_tags")
    def test_determine_next_version_on_release_branch_with_stable_and_active_patch_rc(
        self, mock_get_tags, mock_get_branch
    ):
        mock_get_branch.return_value = "release/0.37"
        # 0.37.0 stable exists, and 0.37.1-rc0 exists (but no stable 0.37.1 yet)
        mock_get_tags.return_value = ["0.37.0", "0.37.1-rc0", "0.36.0"]

        next_version = releaser.determine_next_version()

        # Should target 0.37.1, not 0.37.2
        self.assertEqual(next_version, "0.37.1")

    @patch("tools.private.release.release.git.get_current_branch")
    def test_determine_next_version_on_main_branch_fallback(self, mock_get_branch):
        mock_get_branch.return_value = "main"
        # Should fallback to default behavior (which uses mock_get_latest_version from setUp)
        self.mock_get_latest_version.return_value = "1.2.3"
        (self.tmpdir / "mock_file.bzl").write_text("no markers here")

        next_version = releaser.determine_next_version()

        self.assertEqual(next_version, "1.2.4")


if __name__ == "__main__":
    unittest.main()
