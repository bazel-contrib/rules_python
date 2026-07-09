import unittest
from unittest.mock import MagicMock, patch

from tests.tools.private.release.release_test_helper import (
    TempDirTestCase,
    _mock_git_and_gh,
)
from tools.private.release.gh import (
    MultipleTrackingIssuesError,
    NoTrackingIssueError,
)
from tools.private.release.prepare import Prepare


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
        result = Prepare(args, self.mock_git, self.mock_gh).run()

        # Assert
        self.assertEqual(result, 0)
        self.mock_gh.get_release_tracking_issue.assert_called_once_with("2.0.0")
        self.mock_gh.create_tracking_issue.assert_not_called()
        self.mock_gh.create_pr.assert_called_once_with(
            title="Prepare release v2.0.0",
            body="Work towards #123",
            base="main",
        )
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
        result = Prepare(args, self.mock_git, self.mock_gh).run()

        # Assert
        self.assertEqual(result, 0)
        self.mock_gh.get_release_tracking_issue.assert_called_once_with("2.0.0")
        self.mock_gh.create_tracking_issue.assert_called_once_with(
            "2.0.0", "dummy template content"
        )
        self.mock_gh.create_pr.assert_called_once_with(
            title="Prepare release v2.0.0",
            body="Work towards #123",
            base="main",
        )
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
        result = Prepare(args, self.mock_git, self.mock_gh).run()

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
        result = Prepare(args, self.mock_git, self.mock_gh).run()

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
    def test_prepare_use_associated_pr_from_tracking_issue(
        self, mock_replace, mock_changelog
    ):
        # Arrange
        args = MagicMock(version="2.0.0", issue=None, dry_run=False)
        self.mock_git.status.side_effect = ["", ""]
        self.mock_git.branch_exists.return_value = True
        self.mock_gh.get_release_tracking_issue.side_effect = None
        self.mock_gh.get_release_tracking_issue.return_value = 123
        self.mock_gh.get_open_pr.return_value = None
        # PR #456 is already associated in the tracking issue
        self.mock_gh.get_issue_body.return_value = (
            "- [ ] Prepare Release | status=pending pr=#456"
        )

        # Act
        result = Prepare(args, self.mock_git, self.mock_gh).run()

        # Assert
        self.assertEqual(result, 0)
        self.mock_git.checkout.assert_called_once_with("prepare-2.0.0")
        self.mock_git.commit.assert_not_called()
        self.mock_git.push.assert_called_once_with(
            "origin", "prepare-2.0.0", set_upstream=True, force=True
        )
        self.mock_gh.get_open_pr.assert_called_once_with("prepare-2.0.0")
        self.mock_gh.create_pr.assert_not_called()  # Should NOT create a new PR
        self.mock_gh.update_issue_body.assert_called_once()
        call_args = self.mock_gh.update_issue_body.call_args[0]
        self.assertIn("pr=#456", call_args[1])

    @patch("tools.private.release.prepare.changelog_news")
    @patch("tools.private.release.prepare.replace_version_next")
    def test_prepare_create_pr_when_none_associated(self, mock_replace, mock_changelog):
        # Arrange
        args = MagicMock(version="2.0.0", issue=None, dry_run=False)
        self.mock_git.status.side_effect = ["", ""]
        self.mock_git.branch_exists.return_value = True
        self.mock_gh.get_release_tracking_issue.side_effect = None
        self.mock_gh.get_release_tracking_issue.return_value = 123
        self.mock_gh.get_open_pr.return_value = None
        # No PR associated in the tracking issue
        self.mock_gh.get_issue_body.return_value = "- [ ] Prepare Release"
        self.mock_gh.create_pr.return_value = "https://github.com/foo/bar/pull/789"

        # Act
        result = Prepare(args, self.mock_git, self.mock_gh).run()

        # Assert
        self.assertEqual(result, 0)
        self.mock_git.checkout.assert_called_once_with("prepare-2.0.0")
        self.mock_git.commit.assert_not_called()
        self.mock_git.push.assert_called_once_with(
            "origin", "prepare-2.0.0", set_upstream=True, force=True
        )
        self.mock_gh.get_open_pr.assert_called_once_with("prepare-2.0.0")
        self.mock_gh.create_pr.assert_called_once_with(
            title="Prepare release v2.0.0",
            body="Work towards #123",
            base="main",
        )
        self.mock_gh.update_issue_body.assert_called_once()
        call_args = self.mock_gh.update_issue_body.call_args[0]
        self.assertIn("pr=#789", call_args[1])

    @patch("tools.private.release.prepare.changelog_news")
    @patch("tools.private.release.prepare.replace_version_next")
    def test_prepare_reuse_existing_pr(self, mock_replace, mock_changelog):
        # Arrange
        args = MagicMock(version="2.0.0", issue=None, dry_run=False)
        self.mock_git.status.side_effect = ["", ""]
        self.mock_git.branch_exists.return_value = True
        self.mock_gh.get_release_tracking_issue.side_effect = None
        self.mock_gh.get_release_tracking_issue.return_value = 123
        self.mock_gh.get_open_pr.return_value = {
            "number": 456,
            "url": "https://github.com/foo/bar/pull/456",
        }
        self.mock_gh.get_issue_body.return_value = "- [ ] Prepare Release"

        # Act
        result = Prepare(args, self.mock_git, self.mock_gh).run()

        # Assert
        self.assertEqual(result, 0)
        self.mock_git.checkout.assert_called_once_with("prepare-2.0.0")
        self.mock_git.commit.assert_not_called()
        self.mock_git.push.assert_called_once_with(
            "origin", "prepare-2.0.0", set_upstream=True, force=True
        )
        self.mock_gh.get_open_pr.assert_called_once_with("prepare-2.0.0")
        self.mock_gh.create_pr.assert_not_called()
        self.mock_gh.update_issue_body.assert_called_once()
        call_args = self.mock_gh.update_issue_body.call_args[0]
        self.assertIn("pr=#456", call_args[1])

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
        result = Prepare(args, self.mock_git, self.mock_gh).run()

        # Assert
        self.assertEqual(result, 0)
        self.mock_git.checkout.assert_not_called()
        self.mock_gh.create_tracking_issue.assert_not_called()
        self.mock_gh.create_pr.assert_not_called()
        self.mock_git.add_modified_and_deleted.assert_not_called()


if __name__ == "__main__":
    unittest.main()
