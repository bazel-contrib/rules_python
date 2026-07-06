import unittest
from unittest.mock import patch

from tests.tools.private.release.release_test_helper import TempDirTestCase
from tools.private.release import utils


class GetLatestVersionTest(unittest.TestCase):
    @patch("tools.private.release.git.Git.get_tags")
    def test_get_latest_version_success(self, mock_get_tags):
        mock_get_tags.return_value = ["0.1.0", "1.0.0", "0.2.0"]
        self.assertEqual(utils.get_latest_version(), "1.0.0")

    @patch("tools.private.release.git.Git.get_tags")
    def test_get_latest_version_rc_is_latest(self, mock_get_tags):
        mock_get_tags.return_value = ["0.1.0", "1.0.0", "1.1.0rc0"]
        with self.assertRaisesRegex(
            ValueError, "The latest version is a pre-release version: 1.1.0rc0"
        ):
            utils.get_latest_version()

    @patch("tools.private.release.git.Git.get_tags")
    def test_get_latest_version_no_tags(self, mock_get_tags):
        mock_get_tags.return_value = []
        with self.assertRaisesRegex(
            RuntimeError, "No git tags found matching X.Y.Z or X.Y.ZrcN format."
        ):
            utils.get_latest_version()

    @patch("tools.private.release.git.Git.get_tags")
    def test_get_latest_version_no_matching_tags(self, mock_get_tags):
        mock_get_tags.return_value = ["v1.0", "latest"]
        with self.assertRaisesRegex(
            RuntimeError, "No git tags found matching X.Y.Z or X.Y.ZrcN format."
        ):
            utils.get_latest_version()

    @patch("tools.private.release.git.Git.get_tags")
    def test_get_latest_version_only_rc_tags(self, mock_get_tags):
        mock_get_tags.return_value = ["1.0.0rc0", "1.1.0rc0"]
        with self.assertRaisesRegex(
            ValueError, "The latest version is a pre-release version: 1.1.0rc0"
        ):
            utils.get_latest_version()


class GetLatestRcTagTest(unittest.TestCase):
    @patch("tools.private.release.git.Git.get_tags")
    def test_get_latest_rc_tag_no_tags(self, mock_get_tags):
        mock_get_tags.return_value = []
        self.assertIsNone(utils.get_latest_rc_tag("2.0.0"))

    @patch("tools.private.release.git.Git.get_tags")
    def test_get_latest_rc_tag_no_matching_tags(self, mock_get_tags):
        mock_get_tags.return_value = [
            "1.0.0",
            "2.0.0",
            "v2.0.0-rc0",
            "2.1.0-rc0",
        ]
        self.assertIsNone(utils.get_latest_rc_tag("2.0.0"))

    @patch("tools.private.release.git.Git.get_tags")
    def test_get_latest_rc_tag_success(self, mock_get_tags):
        mock_get_tags.return_value = [
            "2.0.0-rc0",
            "2.0.0-rc2",
            "2.0.0-rc1",
            "2.1.0-rc0",
        ]
        self.assertEqual(utils.get_latest_rc_tag("2.0.0"), "2.0.0-rc2")

    @patch("tools.private.release.git.Git.get_tags")
    def test_get_latest_rc_tag_ignores_v_prefix(self, mock_get_tags):
        mock_get_tags.return_value = ["v2.0.0-rc0", "2.0.0-rc1"]
        self.assertEqual(utils.get_latest_rc_tag("2.0.0"), "2.0.0-rc1")

    @patch("tools.private.release.git.Git.get_remote_tags")
    def test_get_latest_rc_tag_remote_success(self, mock_get_remote_tags):
        mock_get_remote_tags.return_value = [
            "2.0.0-rc0",
            "2.0.0-rc2",
            "2.0.0-rc1",
            "2.1.0-rc0",
        ]
        self.assertEqual(utils.get_latest_rc_tag("2.0.0", remote="origin"), "2.0.0-rc2")
        mock_get_remote_tags.assert_called_once_with("origin")


class DetermineNextVersionTest(TempDirTestCase):
    def setUp(self):
        super().setUp()
        self.mock_get_latest_version = patch(
            "tools.private.release.utils.get_latest_version"
        ).start()
        self.mock_get_current_branch = patch(
            "tools.private.release.git.Git.get_current_branch"
        ).start()
        self.mock_get_current_branch.return_value = "main"
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

    @patch("tools.private.release.git.Git.get_current_branch")
    @patch("tools.private.release.git.Git.get_tags")
    def test_determine_next_version_on_release_branch_with_existing_tags(
        self, mock_get_tags, mock_get_branch
    ):
        mock_get_branch.return_value = "release/0.37"
        mock_get_tags.return_value = ["0.37.0", "0.37.1", "0.36.0"]

        next_version = utils.determine_next_version()

        self.assertEqual(next_version, "0.37.2")

    @patch("tools.private.release.git.Git.get_current_branch")
    @patch("tools.private.release.git.Git.get_tags")
    def test_determine_next_version_on_release_branch_no_tags(
        self, mock_get_tags, mock_get_branch
    ):
        mock_get_branch.return_value = "release/0.38"
        mock_get_tags.return_value = ["0.37.0"]  # No 0.38.x tags

        next_version = utils.determine_next_version()

        self.assertEqual(next_version, "0.38.0")

    @patch("tools.private.release.git.Git.get_current_branch")
    @patch("tools.private.release.git.Git.get_tags")
    def test_determine_next_version_on_release_branch_with_active_rc(
        self, mock_get_tags, mock_get_branch
    ):
        mock_get_branch.return_value = "release/0.37"
        # 0.37.0-rc0 and rc1 exist, but no stable 0.37.0 yet
        mock_get_tags.return_value = ["0.37.0-rc0", "0.37.0-rc1", "0.36.0"]

        next_version = utils.determine_next_version()

        # Should target 0.37.0, not 0.37.1
        self.assertEqual(next_version, "0.37.0")

    @patch("tools.private.release.git.Git.get_current_branch")
    @patch("tools.private.release.git.Git.get_tags")
    def test_determine_next_version_on_release_branch_with_stable_and_active_patch_rc(
        self, mock_get_tags, mock_get_branch
    ):
        mock_get_branch.return_value = "release/0.37"
        # 0.37.0 stable exists, and 0.37.1-rc0 exists (but no stable 0.37.1 yet)
        mock_get_tags.return_value = ["0.37.0", "0.37.1-rc0", "0.36.0"]

        next_version = utils.determine_next_version()

        # Should target 0.37.1, not 0.37.2
        self.assertEqual(next_version, "0.37.1")

    @patch("tools.private.release.git.Git.get_current_branch")
    def test_determine_next_version_on_main_branch_fallback(self, mock_get_branch):
        mock_get_branch.return_value = "main"
        # Should fallback to default behavior (which uses mock_get_latest_version from setUp)
        self.mock_get_latest_version.return_value = "1.2.3"
        (self.tmpdir / "mock_file.bzl").write_text("no markers here")

        next_version = utils.determine_next_version()

        self.assertEqual(next_version, "1.2.4")


class ReplaceVersionNextTest(TempDirTestCase):
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


if __name__ == "__main__":
    unittest.main()
