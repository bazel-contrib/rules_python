import os
import pathlib
import shutil
import tempfile
import unittest
from unittest.mock import MagicMock, patch

from tools.private.release import changelog_news, release as releaser, utils
from tools.private.release.gh import MultipleTrackingIssuesError, NoTrackingIssueError


def _mock_git_and_gh(test_case):
    mock_git = MagicMock()
    mock_gh = MagicMock()
    test_case.mock_git = mock_git
    test_case.mock_gh = mock_gh

    # Patch bindings in modules that import them at module level
    patch("tools.private.release.release.git", new=mock_git).start()
    patch("tools.private.release.prepare.git", new=mock_git).start()
    patch("tools.private.release.utils.git", new=mock_git).start()

    patch("tools.private.release.release.gh", new=mock_gh).start()
    patch("tools.private.release.prepare.gh", new=mock_gh).start()
    mock_gh.MultipleTrackingIssuesError = MultipleTrackingIssuesError
    mock_gh.NoTrackingIssueError = NoTrackingIssueError

    test_case.addCleanup(patch.stopall)

    # Apply safe defaults
    mock_git.get_current_branch.return_value = None
    mock_git.get_tags.return_value = []
    mock_git.get_tags_at_head.return_value = []
    mock_git.status.return_value = ""
    mock_git.branch_exists.return_value = False
    mock_git.tag_exists.return_value = False
    mock_gh.get_release_tracking_issue.side_effect = NoTrackingIssueError("Not found")


class TempDirTestCase(unittest.TestCase):
    def setUp(self):
        self.tmpdir = pathlib.Path(tempfile.mkdtemp())
        self.original_cwd = os.getcwd()
        self.addCleanup(shutil.rmtree, self.tmpdir)
        os.chdir(self.tmpdir)
        self.addCleanup(os.chdir, self.original_cwd)


class ReleaserTest(TempDirTestCase):
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

        utils.replace_version_next("0.28.0")

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
        utils.replace_version_next(version)

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
    @patch("tools.private.release.git.get_tags")
    def test_get_latest_version_success(self, mock_get_tags):
        mock_get_tags.return_value = ["0.1.0", "1.0.0", "0.2.0"]
        self.assertEqual(utils.get_latest_version(), "1.0.0")

    @patch("tools.private.release.git.get_tags")
    def test_get_latest_version_rc_is_latest(self, mock_get_tags):
        mock_get_tags.return_value = ["0.1.0", "1.0.0", "1.1.0rc0"]
        with self.assertRaisesRegex(
            ValueError, "The latest version is a pre-release version: 1.1.0rc0"
        ):
            utils.get_latest_version()

    @patch("tools.private.release.git.get_tags")
    def test_get_latest_version_no_tags(self, mock_get_tags):
        mock_get_tags.return_value = []
        with self.assertRaisesRegex(
            RuntimeError, "No git tags found matching X.Y.Z or X.Y.ZrcN format."
        ):
            utils.get_latest_version()

    @patch("tools.private.release.git.get_tags")
    def test_get_latest_version_no_matching_tags(self, mock_get_tags):
        mock_get_tags.return_value = ["v1.0", "latest"]
        with self.assertRaisesRegex(
            RuntimeError, "No git tags found matching X.Y.Z or X.Y.ZrcN format."
        ):
            utils.get_latest_version()

    @patch("tools.private.release.git.get_tags")
    def test_get_latest_version_only_rc_tags(self, mock_get_tags):
        mock_get_tags.return_value = ["1.0.0rc0", "1.1.0rc0"]
        with self.assertRaisesRegex(
            ValueError, "The latest version is a pre-release version: 1.1.0rc0"
        ):
            utils.get_latest_version()


class GetLatestRcTagTest(unittest.TestCase):
    @patch("tools.private.release.git.get_tags")
    def test_get_latest_rc_tag_no_tags(self, mock_get_tags):
        mock_get_tags.return_value = []
        self.assertIsNone(utils.get_latest_rc_tag("2.0.0"))

    @patch("tools.private.release.git.get_tags")
    def test_get_latest_rc_tag_no_matching_tags(self, mock_get_tags):
        mock_get_tags.return_value = ["1.0.0", "2.0.0", "v2.0.0-rc0", "2.1.0-rc0"]
        self.assertIsNone(utils.get_latest_rc_tag("2.0.0"))

    @patch("tools.private.release.git.get_tags")
    def test_get_latest_rc_tag_success(self, mock_get_tags):
        mock_get_tags.return_value = [
            "2.0.0-rc0",
            "2.0.0-rc2",
            "2.0.0-rc1",
            "2.1.0-rc0",
        ]
        self.assertEqual(utils.get_latest_rc_tag("2.0.0"), "2.0.0-rc2")

    @patch("tools.private.release.git.get_tags")
    def test_get_latest_rc_tag_ignores_v_prefix(self, mock_get_tags):
        mock_get_tags.return_value = ["v2.0.0-rc0", "2.0.0-rc1"]
        self.assertEqual(utils.get_latest_rc_tag("2.0.0"), "2.0.0-rc1")


class DetermineNextVersionTest(TempDirTestCase):
    def setUp(self):
        super().setUp()
        self.mock_get_latest_version = patch(
            "tools.private.release.utils.get_latest_version"
        ).start()
        self.addCleanup(patch.stopall)

    def test_no_markers(self):
        (self.tmpdir / "mock_file.bzl").write_text("no markers here")
        self.mock_get_latest_version.return_value = "1.2.3"

        next_version = utils.determine_next_version()

        self.assertEqual(next_version, "1.2.4")

    def test_only_patch(self):
        (self.tmpdir / "mock_file.bzl").write_text(
            ":::{versionchanged} VERSION_NEXT_PATCH"
        )
        self.mock_get_latest_version.return_value = "1.2.3"

        next_version = utils.determine_next_version()

        self.assertEqual(next_version, "1.2.4")

    def test_only_feature(self):
        (self.tmpdir / "mock_file.bzl").write_text(
            ":::{versionadded} VERSION_NEXT_FEATURE"
        )
        self.mock_get_latest_version.return_value = "1.2.3"

        next_version = utils.determine_next_version()

        self.assertEqual(next_version, "1.3.0")

    def test_both_markers(self):
        (self.tmpdir / "mock_file_patch.bzl").write_text(
            ":::{versionchanged} VERSION_NEXT_PATCH"
        )
        (self.tmpdir / "mock_file_feature.bzl").write_text(
            ":::{versionadded} VERSION_NEXT_FEATURE"
        )
        self.mock_get_latest_version.return_value = "1.2.3"

        next_version = utils.determine_next_version()

        self.assertEqual(next_version, "1.3.0")

    @patch("tools.private.release.git.get_current_branch")
    @patch("tools.private.release.git.get_tags")
    def test_determine_next_version_on_release_branch_with_existing_tags(
        self, mock_get_tags, mock_get_branch
    ):
        mock_get_branch.return_value = "release/0.37"
        mock_get_tags.return_value = ["0.37.0", "0.37.1", "0.36.0"]

        next_version = utils.determine_next_version()

        self.assertEqual(next_version, "0.37.2")

    @patch("tools.private.release.git.get_current_branch")
    @patch("tools.private.release.git.get_tags")
    def test_determine_next_version_on_release_branch_no_tags(
        self, mock_get_tags, mock_get_branch
    ):
        mock_get_branch.return_value = "release/0.38"
        mock_get_tags.return_value = ["0.37.0"]  # No 0.38.x tags

        next_version = utils.determine_next_version()

        self.assertEqual(next_version, "0.38.0")

    @patch("tools.private.release.git.get_current_branch")
    @patch("tools.private.release.git.get_tags")
    def test_determine_next_version_on_release_branch_with_active_rc(
        self, mock_get_tags, mock_get_branch
    ):
        mock_get_branch.return_value = "release/0.37"
        # 0.37.0-rc0 and rc1 exist, but no stable 0.37.0 yet
        mock_get_tags.return_value = ["0.37.0-rc0", "0.37.0-rc1", "0.36.0"]

        next_version = utils.determine_next_version()

        # Should target 0.37.0, not 0.37.1
        self.assertEqual(next_version, "0.37.0")

    @patch("tools.private.release.git.get_current_branch")
    @patch("tools.private.release.git.get_tags")
    def test_determine_next_version_on_release_branch_with_stable_and_active_patch_rc(
        self, mock_get_tags, mock_get_branch
    ):
        mock_get_branch.return_value = "release/0.37"
        # 0.37.0 stable exists, and 0.37.1-rc0 exists (but no stable 0.37.1 yet)
        mock_get_tags.return_value = ["0.37.0", "0.37.1-rc0", "0.36.0"]

        next_version = utils.determine_next_version()

        # Should target 0.37.1, not 0.37.2
        self.assertEqual(next_version, "0.37.1")

    @patch("tools.private.release.git.get_current_branch")
    def test_determine_next_version_on_main_branch_fallback(self, mock_get_branch):
        mock_get_branch.return_value = "main"
        # Should fallback to default behavior (which uses mock_get_latest_version from setUp)
        self.mock_get_latest_version.return_value = "1.2.3"
        (self.tmpdir / "mock_file.bzl").write_text("no markers here")

        next_version = utils.determine_next_version()

        self.assertEqual(next_version, "1.2.4")


class CmdPrepareTest(TempDirTestCase):
    def setUp(self):
        super().setUp()
        _mock_git_and_gh(self)

    @patch("tools.private.release.prepare.changelog_news")
    @patch("tools.private.release.prepare.replace_version_next")
    def test_prepare_success_existing_issue(self, mock_replace, mock_changelog):
        # Arrange
        args = MagicMock(version="2.0.0", issue=None, dry_run=False)
        self.mock_git.status.side_effect = ["", "M  foo"]
        self.mock_git.branch_exists.return_value = False
        self.mock_gh.get_release_tracking_issue.side_effect = None
        self.mock_gh.get_release_tracking_issue.return_value = 123
        self.mock_gh.create_pr.return_value = "https://github.com/foo/bar/pull/456"
        self.mock_gh.get_issue_body.return_value = "- [ ] Prepare Release"

        # Act
        result = releaser.cmd_prepare(args)

        # Assert
        self.assertEqual(result, 0)
        self.mock_gh.get_release_tracking_issue.assert_called_once_with("2.0.0")
        self.mock_gh.create_tracking_issue.assert_not_called()
        self.mock_gh.create_pr.assert_called_once_with("2.0.0", 123)
        self.mock_git.add_modified_and_deleted.assert_called_once()

    @patch("tools.private.release.prepare.changelog_news")
    @patch("tools.private.release.prepare.replace_version_next")
    def test_prepare_success_create_issue(self, mock_replace, mock_changelog):
        # Arrange
        template_dir = self.tmpdir / ".github" / "ISSUE_TEMPLATE"
        template_dir.mkdir(parents=True, exist_ok=True)
        template_file = template_dir / "release_tracking_template.md"
        template_file.write_text("dummy template content")

        args = MagicMock(version="2.0.0", issue=None, dry_run=False)
        self.mock_git.status.side_effect = ["", "M  foo"]
        self.mock_git.branch_exists.return_value = False
        self.mock_gh.get_release_tracking_issue.side_effect = NoTrackingIssueError(
            "Not found"
        )
        self.mock_gh.create_tracking_issue.return_value = 123
        self.mock_gh.create_pr.return_value = "https://github.com/foo/bar/pull/456"
        self.mock_gh.get_issue_body.return_value = "- [ ] Prepare Release"

        # Act
        result = releaser.cmd_prepare(args)

        # Assert
        self.assertEqual(result, 0)
        self.mock_gh.get_release_tracking_issue.assert_called_once_with("2.0.0")
        self.mock_gh.create_tracking_issue.assert_called_once_with(
            "2.0.0", "dummy template content"
        )
        self.mock_gh.create_pr.assert_called_once_with("2.0.0", 123)
        self.mock_git.add_modified_and_deleted.assert_called_once()

    @patch("tools.private.release.prepare.changelog_news")
    @patch("tools.private.release.prepare.replace_version_next")
    def test_prepare_ambiguous_issue(self, mock_replace, mock_changelog):
        # Arrange
        args = MagicMock(version="2.0.0", issue=None, dry_run=False)
        self.mock_git.status.side_effect = ["", "M  foo"]
        self.mock_git.branch_exists.return_value = False
        self.mock_gh.get_release_tracking_issue.side_effect = (
            MultipleTrackingIssuesError("Multiple open tracking issues")
        )

        # Act
        result = releaser.cmd_prepare(args)

        # Assert
        self.assertEqual(result, 1)
        self.mock_gh.get_release_tracking_issue.assert_called_once_with("2.0.0")
        self.mock_gh.create_tracking_issue.assert_not_called()
        self.mock_gh.create_pr.assert_not_called()
        self.mock_git.add_modified_and_deleted.assert_not_called()

    @patch("tools.private.release.prepare.changelog_news")
    @patch("tools.private.release.prepare.replace_version_next")
    def test_prepare_dry_run(self, mock_replace, mock_changelog):
        # Arrange
        args = MagicMock(version="2.0.0", issue=None, dry_run=True)
        self.mock_git.status.side_effect = [""]
        self.mock_gh.get_release_tracking_issue.side_effect = None
        self.mock_gh.get_release_tracking_issue.return_value = 123

        # Act
        result = releaser.cmd_prepare(args)

        # Assert
        self.assertEqual(result, 0)
        self.mock_git.checkout.assert_not_called()
        self.mock_git.commit.assert_not_called()
        self.mock_git.push.assert_not_called()
        self.mock_gh.create_pr.assert_not_called()
        self.mock_gh.update_issue_body.assert_not_called()
        self.mock_git.fetch.assert_called_once()
        self.mock_gh.get_release_tracking_issue.assert_called_once_with("2.0.0")
        self.mock_git.add_modified_and_deleted.assert_not_called()

    @patch("tools.private.release.prepare.changelog_news")
    @patch("tools.private.release.prepare.replace_version_next")
    def test_prepare_dry_run_no_issue(self, mock_replace, mock_changelog):
        # Arrange
        template_dir = self.tmpdir / ".github" / "ISSUE_TEMPLATE"
        template_dir.mkdir(parents=True, exist_ok=True)
        template_file = template_dir / "release_tracking_template.md"
        template_file.write_text("dummy template content")

        args = MagicMock(version="2.0.0", issue=None, dry_run=True)
        self.mock_git.status.side_effect = [""]
        self.mock_gh.get_release_tracking_issue.side_effect = NoTrackingIssueError(
            "Not found"
        )

        # Act
        result = releaser.cmd_prepare(args)

        # Assert
        self.assertEqual(result, 0)
        self.mock_git.checkout.assert_not_called()
        self.mock_gh.create_tracking_issue.assert_not_called()
        self.mock_gh.create_pr.assert_not_called()
        self.mock_git.add_modified_and_deleted.assert_not_called()


class CmdCreateRcTest(unittest.TestCase):
    def setUp(self):
        _mock_git_and_gh(self)

    def test_create_rc_success_first_rc(self):
        # Arrange
        args = MagicMock(issue=123)
        self.mock_gh.get_issue_title.return_value = "Release 2.0.0"
        self.mock_gh.get_issue_body.return_value = """
## Checklist
- [x] Prepare Release | status=done pr=#122 commit=abcdef12
- [x] Create Release branch | status=done branch=release/2.0 commit=abcdef12
- [ ] Tag RC0 | status=pending
"""
        self.mock_git.get_tags.return_value = []
        self.mock_git.get_tags_at_head.return_value = []
        self.mock_git.get_commit_sha.return_value = "1234567890"

        # Act
        result = releaser.cmd_create_rc(args)

        # Assert
        self.assertEqual(result, 0)
        self.mock_git.tag.assert_called_once_with("2.0.0-rc0", "HEAD")
        self.mock_git.push.assert_called_once_with("origin", "2.0.0-rc0")

        self.mock_gh.update_issue_body.assert_called_once()
        call_args = self.mock_gh.update_issue_body.call_args[0]
        self.assertEqual(call_args[0], 123)
        self.assertIn("tag=2.0.0-rc0", call_args[1])
        self.assertIn("commit=12345678", call_args[1])

        self.mock_gh.post_issue_comment.assert_called_once()

    def test_create_rc_success_next_rc(self):
        # Arrange
        args = MagicMock(issue=123)
        self.mock_gh.get_issue_title.return_value = "Release 2.0.0"
        self.mock_gh.get_issue_body.return_value = """
## Checklist
- [x] Prepare Release | status=done pr=#122 commit=abcdef12
- [x] Create Release branch | status=done branch=release/2.0 commit=abcdef12
- [x] Tag RC0 | status=done tag=2.0.0-rc0 commit=abcdef12
- [ ] Tag RC1 | status=pending
"""
        self.mock_git.get_tags.return_value = ["2.0.0-rc0"]
        self.mock_git.get_tags_at_head.return_value = []
        self.mock_git.get_commit_sha.return_value = "1234567890"

        # Act
        result = releaser.cmd_create_rc(args)

        # Assert
        self.assertEqual(result, 0)
        self.mock_git.tag.assert_called_once_with("2.0.0-rc1", "HEAD")
        self.mock_git.push.assert_called_once_with("origin", "2.0.0-rc1")

        self.mock_gh.update_issue_body.assert_called_once()
        call_args = self.mock_gh.update_issue_body.call_args[0]
        self.assertEqual(call_args[0], 123)
        self.assertIn("tag=2.0.0-rc1", call_args[1])

        self.mock_gh.post_issue_comment.assert_called_once()

    def test_create_rc_already_tagged(self):
        # Arrange
        args = MagicMock(issue=123)
        self.mock_gh.get_issue_title.return_value = "Release 2.0.0"
        self.mock_gh.get_issue_body.return_value = """
## Checklist
- [x] Prepare Release | status=done pr=#122 commit=abcdef12
- [x] Create Release branch | status=done branch=release/2.0 commit=abcdef12
- [ ] Tag RC0 | status=pending
"""
        self.mock_git.get_tags.return_value = []
        self.mock_git.get_tags_at_head.return_value = ["2.0.0-rc0"]

        # Act
        result = releaser.cmd_create_rc(args)

        # Assert
        self.assertEqual(result, 0)
        self.mock_git.tag.assert_not_called()
        self.mock_git.push.assert_not_called()
        self.mock_gh.update_issue_body.assert_not_called()


class CmdPromoteRcTest(unittest.TestCase):
    def setUp(self):
        _mock_git_and_gh(self)

    def test_promote_rc_success(self):
        # Arrange
        args = MagicMock(version="2.0.0", issue=123, dry_run=False)
        self.mock_git.get_tags.return_value = ["2.0.0-rc0", "2.0.0-rc1"]
        self.mock_git.get_commit_sha.return_value = "abcdef123456"
        self.mock_git.tag_exists.return_value = False
        initial_body = "- [ ] Tag Final"
        self.mock_gh.get_issue_body.return_value = initial_body

        # Act
        result = releaser.cmd_promote_rc(args)

        # Assert
        self.assertEqual(result, 0)
        self.mock_git.fetch.assert_called_once_with("upstream", tags=True, force=True)
        self.mock_git.get_commit_sha.assert_called_once_with("2.0.0-rc1")
        self.mock_git.checkout.assert_not_called()
        self.mock_git.tag_exists.assert_called_once_with("2.0.0")
        self.mock_git.tag.assert_called_once_with("2.0.0", "abcdef123456")
        self.mock_git.push.assert_called_once_with("upstream", "2.0.0")

        # Verify issue update
        self.mock_gh.get_issue_body.assert_called_once_with(123)
        expected_updated_body = (
            "- [x] Tag Final | status=done tag=2.0.0 commit=abcdef12"
        )
        self.mock_gh.update_issue_body.assert_called_once_with(
            123, expected_updated_body
        )
        expected_comment = (
            "Version 2.0.0 has been tagged.\n\n"
            "- **Release Page**: https://github.com/bazel-contrib/rules_python/releases/tag/2.0.0\n"
            '- **BCR PR Search**: [is:pr ("bazel-contrib/rules_python" in:title) ("@2.0.0" in:title)](https://github.com/bazelbuild/bazel-central-registry/pulls?q=is%3Apr%20%28%22bazel-contrib/rules_python%22%20in%3Atitle%29%20%28%22%402.0.0%22%20in%3Atitle%29)'
        )
        self.mock_gh.post_issue_comment.assert_called_once_with(123, expected_comment)

    def test_promote_rc_resolve_issue_success(self):
        # Arrange
        args = MagicMock(version="2.0.0", issue=None, dry_run=False)
        self.mock_git.get_tags.return_value = ["2.0.0-rc1"]
        self.mock_git.tag_exists.return_value = False
        self.mock_gh.get_release_tracking_issue.side_effect = None
        self.mock_gh.get_release_tracking_issue.return_value = 123
        self.mock_git.get_commit_sha.return_value = "abcdef123456"
        initial_body = "- [ ] Tag Final"
        self.mock_gh.get_issue_body.return_value = initial_body

        # Act
        result = releaser.cmd_promote_rc(args)

        # Assert
        self.assertEqual(result, 0)
        self.mock_gh.get_release_tracking_issue.assert_called_once_with("2.0.0")
        self.mock_git.get_commit_sha.assert_called_once_with("2.0.0-rc1")
        self.mock_git.checkout.assert_not_called()
        self.mock_git.tag.assert_called_once_with("2.0.0", "abcdef123456")
        self.mock_git.push.assert_called_once_with("upstream", "2.0.0")
        self.mock_gh.get_issue_body.assert_called_once_with(123)
        expected_updated_body = (
            "- [x] Tag Final | status=done tag=2.0.0 commit=abcdef12"
        )
        self.mock_gh.update_issue_body.assert_called_once_with(
            123, expected_updated_body
        )
        expected_comment = (
            "Version 2.0.0 has been tagged.\n\n"
            "- **Release Page**: https://github.com/bazel-contrib/rules_python/releases/tag/2.0.0\n"
            '- **BCR PR Search**: [is:pr ("bazel-contrib/rules_python" in:title) ("@2.0.0" in:title)](https://github.com/bazelbuild/bazel-central-registry/pulls?q=is%3Apr%20%28%22bazel-contrib/rules_python%22%20in%3Atitle%29%20%28%22%402.0.0%22%20in%3Atitle%29)'
        )
        self.mock_gh.post_issue_comment.assert_called_once_with(123, expected_comment)

    def test_promote_rc_defaults_to_determine_next_version(self):
        # Arrange
        args = MagicMock(version=None, issue=123, dry_run=False)
        self.mock_git.get_current_branch.return_value = "release/2.0"
        self.mock_git.get_tags.return_value = ["2.0.0", "2.0.1-rc0"]
        self.mock_git.get_commit_sha.return_value = "12345678"
        self.mock_git.tag_exists.return_value = False
        initial_body = "- [ ] Tag Final"
        self.mock_gh.get_issue_body.return_value = initial_body

        # Act
        result = releaser.cmd_promote_rc(args)

        # Assert
        self.assertEqual(result, 0)
        self.mock_git.get_current_branch.assert_called_once()
        self.assertTrue(self.mock_git.get_tags.call_count >= 2)

        self.mock_git.checkout.assert_not_called()
        self.mock_git.get_commit_sha.assert_called_once_with("2.0.1-rc0")
        self.mock_git.tag.assert_called_once_with("2.0.1", "12345678")
        self.mock_git.push.assert_called_once_with("upstream", "2.0.1")

        expected_updated_body = (
            "- [x] Tag Final | status=done tag=2.0.1 commit=12345678"
        )
        self.mock_gh.update_issue_body.assert_called_once_with(
            123, expected_updated_body
        )
        expected_comment = (
            "Version 2.0.1 has been tagged.\n\n"
            "- **Release Page**: https://github.com/bazel-contrib/rules_python/releases/tag/2.0.1\n"
            '- **BCR PR Search**: [is:pr ("bazel-contrib/rules_python" in:title) ("@2.0.1" in:title)](https://github.com/bazelbuild/bazel-central-registry/pulls?q=is%3Apr%20%28%22bazel-contrib/rules_python%22%20in%3Atitle%29%20%28%22%402.0.1%22%20in%3Atitle%29)'
        )
        self.mock_gh.post_issue_comment.assert_called_once_with(123, expected_comment)

    def test_promote_rc_dry_run_success(self):
        # Arrange
        args = MagicMock(version="2.0.0", issue=123, dry_run=True)
        self.mock_git.get_tags.return_value = ["2.0.0-rc0", "2.0.0-rc1"]
        self.mock_git.get_commit_sha.return_value = "abcdef123456"
        self.mock_git.tag_exists.return_value = False
        initial_body = "- [ ] Tag Final"
        self.mock_gh.get_issue_body.return_value = initial_body

        # Act
        result = releaser.cmd_promote_rc(args)

        # Assert
        self.assertEqual(result, 0)
        self.mock_git.fetch.assert_called_once_with("upstream", tags=True, force=True)
        self.mock_git.get_commit_sha.assert_called_once_with("2.0.0-rc1")
        self.mock_git.tag_exists.assert_called_once_with("2.0.0")

        # Core dry-run assertions: NO modifications
        self.mock_git.tag.assert_not_called()
        self.mock_git.push.assert_not_called()
        self.mock_gh.update_issue_body.assert_not_called()
        self.mock_gh.post_issue_comment.assert_not_called()

    def test_promote_rc_tag_already_exists(self):
        # Arrange
        args = MagicMock(version="2.0.0", issue=123)
        self.mock_git.get_tags.return_value = ["2.0.0-rc1"]
        self.mock_git.tag_exists.return_value = True

        # Act
        result = releaser.cmd_promote_rc(args)

        # Assert
        self.assertEqual(result, 1)
        self.mock_git.checkout.assert_not_called()
        self.mock_git.tag.assert_not_called()
        self.mock_git.push.assert_not_called()
        self.mock_gh.get_issue_body.assert_not_called()
        self.mock_gh.update_issue_body.assert_not_called()

    def test_promote_rc_issue_not_found(self):
        # Arrange
        args = MagicMock(version="2.0.0", issue=None)
        self.mock_git.get_tags.return_value = ["2.0.0-rc1"]
        self.mock_git.tag_exists.return_value = False
        self.mock_gh.get_release_tracking_issue.side_effect = NoTrackingIssueError(
            "Not found"
        )

        # Act
        result = releaser.cmd_promote_rc(args)

        # Assert
        self.assertEqual(result, 1)
        self.mock_gh.get_release_tracking_issue.assert_called_once_with("2.0.0")
        self.mock_git.checkout.assert_not_called()
        self.mock_git.tag.assert_not_called()
        self.mock_git.push.assert_not_called()
        self.mock_gh.get_issue_body.assert_not_called()

    def test_promote_rc_issue_malformed(self):
        # Arrange
        args = MagicMock(version="2.0.0", issue=123)
        self.mock_git.get_tags.return_value = ["2.0.0-rc1"]
        self.mock_git.tag_exists.return_value = False
        self.mock_git.get_commit_sha.return_value = "abcdef123456"
        initial_body = "malformed body"
        self.mock_gh.get_issue_body.return_value = initial_body

        # Act
        result = releaser.cmd_promote_rc(args)

        # Assert
        self.assertEqual(result, 1)
        self.mock_gh.get_issue_body.assert_called_once_with(123)
        self.mock_git.checkout.assert_not_called()
        self.mock_git.tag.assert_not_called()
        self.mock_git.push.assert_not_called()
        self.mock_gh.update_issue_body.assert_not_called()

    def test_promote_rc_no_rc_found(self):
        # Arrange
        args = MagicMock(version="2.0.0", issue=123)
        self.mock_git.get_tags.return_value = []

        # Act
        result = releaser.cmd_promote_rc(args)

        # Assert
        self.assertEqual(result, 1)
        self.mock_git.checkout.assert_not_called()
        self.mock_git.tag.assert_not_called()
        self.mock_gh.get_issue_body.assert_not_called()


if __name__ == "__main__":
    unittest.main()
