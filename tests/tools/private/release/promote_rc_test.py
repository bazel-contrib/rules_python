import argparse
import unittest
from unittest.mock import call, patch

from tests.tools.private.release.release_test_helper import _mock_git_and_gh
from tools.private.release.gh import NoTrackingIssueError
from tools.private.release.promote_rc import PromoteRc


class CmdPromoteRcTest(unittest.TestCase):
    def setUp(self):
        _mock_git_and_gh(self)

    def test_promote_rc_success(self):
        # Arrange
        args = argparse.Namespace(
            version="2.0.0", issue=123, dry_run=False, remote="my-remote"
        )
        self.mock_git.get_remote_tags.return_value = ["2.0.0-rc0", "2.0.0-rc1"]
        self.mock_git.get_commit_sha.return_value = "abcdef123456"
        self.mock_git.tag_exists.return_value = False
        initial_body = "- [ ] Tag Final"
        self.mock_gh.get_issue_body.return_value = initial_body

        # Act
        result = PromoteRc(args, self.mock_git, self.mock_gh).run()

        # Assert
        self.assertEqual(result, 0)
        self.mock_git.fetch.assert_has_calls(
            [
                call("my-remote", tags=True, force=True),
                call("my-remote", refspec="release/2.0"),
            ]
        )
        self.mock_git.get_commit_sha.assert_has_calls(
            [call("2.0.0-rc1"), call(remote_ref="my-remote/release/2.0")]
        )
        self.mock_git.checkout.assert_not_called()
        self.mock_git.tag_exists.assert_called_once_with("2.0.0")
        self.mock_git.tag.assert_called_once_with("2.0.0", "abcdef123456")
        self.mock_git.push.assert_called_once_with("my-remote", "2.0.0")

        # Verify issue update
        self.mock_gh.get_issue_body.assert_called_once_with(123)
        expected_updated_body = (
            "- [x] Tag Final | status=done tag=2.0.0 commit= abcdef12"
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
        args = argparse.Namespace(
            version="2.0.0", issue=None, dry_run=False, remote="my-remote"
        )
        self.mock_git.get_remote_tags.return_value = ["2.0.0-rc1"]
        self.mock_git.tag_exists.return_value = False
        self.mock_gh.get_release_tracking_issue.side_effect = None
        self.mock_gh.get_release_tracking_issue.return_value = 123
        self.mock_git.get_commit_sha.return_value = "abcdef123456"
        initial_body = "- [ ] Tag Final"
        self.mock_gh.get_issue_body.return_value = initial_body

        # Act
        result = PromoteRc(args, self.mock_git, self.mock_gh).run()

        # Assert
        self.assertEqual(result, 0)
        self.mock_git.fetch.assert_has_calls(
            [
                call("my-remote", tags=True, force=True),
                call("my-remote", refspec="release/2.0"),
            ]
        )
        self.mock_gh.get_release_tracking_issue.assert_called_once_with("2.0.0")
        self.mock_git.get_commit_sha.assert_has_calls(
            [call("2.0.0-rc1"), call(remote_ref="my-remote/release/2.0")]
        )
        self.mock_git.checkout.assert_not_called()
        self.mock_git.tag.assert_called_once_with("2.0.0", "abcdef123456")
        self.mock_git.push.assert_called_once_with("my-remote", "2.0.0")
        self.mock_gh.get_issue_body.assert_called_once_with(123)
        expected_updated_body = (
            "- [x] Tag Final | status=done tag=2.0.0 commit= abcdef12"
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

    def test_promote_rc_resolves_version_from_issue(self):
        # Arrange
        args = argparse.Namespace(
            version=None, issue=123, dry_run=False, remote="my-remote"
        )
        self.mock_gh.get_issue_title.return_value = "Release 2.0.1"
        self.mock_git.get_remote_tags.return_value = ["2.0.1-rc0"]
        self.mock_git.get_commit_sha.return_value = "12345678"
        self.mock_git.tag_exists.return_value = False
        initial_body = "- [ ] Tag Final"
        self.mock_gh.get_issue_body.return_value = initial_body

        # Act
        result = PromoteRc(args, self.mock_git, self.mock_gh).run()

        # Assert
        self.assertEqual(result, 0)
        self.mock_git.fetch.assert_has_calls(
            [
                call("my-remote", tags=True, force=True),
                call("my-remote", refspec="release/2.0"),
            ]
        )
        self.mock_git.get_current_branch.assert_not_called()
        self.mock_git.get_tags.assert_not_called()
        self.mock_git.get_remote_tags.assert_called_once_with("my-remote")

        self.mock_git.checkout.assert_not_called()
        self.mock_git.get_commit_sha.assert_has_calls(
            [call("2.0.1-rc0"), call(remote_ref="my-remote/release/2.0")]
        )
        self.mock_git.tag.assert_called_once_with("2.0.1", "12345678")
        self.mock_git.push.assert_called_once_with("my-remote", "2.0.1")

        expected_updated_body = (
            "- [x] Tag Final | status=done tag=2.0.1 commit= 12345678"
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

    @patch("builtins.print")
    def test_promote_rc_dry_run_success(self, mock_print):
        # Arrange
        args = argparse.Namespace(
            version="2.0.0", issue=123, dry_run=True, remote="my-remote"
        )
        self.mock_git.get_remote_tags.return_value = ["2.0.0-rc0", "2.0.0-rc1"]
        self.mock_git.get_commit_sha.return_value = "abcdef123456"
        self.mock_git.tag_exists.return_value = False
        initial_body = "- [ ] Tag Final"
        self.mock_gh.get_issue_body.return_value = initial_body

        # Act
        result = PromoteRc(args, self.mock_git, self.mock_gh).run()

        # Assert
        self.assertEqual(result, 0)
        self.mock_git.fetch.assert_has_calls(
            [
                call("my-remote", tags=True, force=True),
                call("my-remote", refspec="release/2.0"),
            ]
        )
        self.mock_git.get_commit_sha.assert_has_calls(
            [call("2.0.0-rc1"), call(remote_ref="my-remote/release/2.0")]
        )
        self.mock_git.tag_exists.assert_called_once_with("2.0.0")

        # Core dry-run assertions: NO modifications
        self.mock_git.tag.assert_not_called()
        self.mock_git.push.assert_not_called()
        self.mock_gh.update_issue_body.assert_not_called()
        self.mock_gh.post_issue_comment.assert_not_called()

        mock_print.assert_has_calls(
            [
                call("Verifying tracking issue #123 format..."),
                call("Fetching remote branch my-remote/release/2.0..."),
                call(
                    "[DRY RUN] Pre-conditions passed successfully for promoting"
                    " 2.0.0-rc1 to 2.0.0."
                ),
                call("[DRY RUN] Would tag commit abcdef12 as 2.0.0"),
                call("[DRY RUN] Would push tag 2.0.0 to my-remote"),
                call("[DRY RUN] Would update tracking issue #123 checklist"),
                call("[DRY RUN] Would post comment to tracking issue #123"),
            ]
        )

    def test_promote_rc_tag_already_exists(self):
        # Arrange
        args = argparse.Namespace(
            version="2.0.0", issue=123, dry_run=False, remote="my-remote"
        )
        self.mock_git.get_remote_tags.return_value = ["2.0.0-rc1"]
        self.mock_git.tag_exists.return_value = True

        # Act
        result = PromoteRc(args, self.mock_git, self.mock_gh).run()

        # Assert
        self.assertEqual(result, 1)
        self.mock_git.checkout.assert_not_called()
        self.mock_git.tag.assert_not_called()
        self.mock_git.push.assert_not_called()
        self.mock_gh.get_issue_body.assert_not_called()
        self.mock_gh.update_issue_body.assert_not_called()

    def test_promote_rc_issue_not_found(self):
        # Arrange
        args = argparse.Namespace(
            version="2.0.0", issue=None, dry_run=False, remote="my-remote"
        )
        self.mock_git.get_remote_tags.return_value = ["2.0.0-rc1"]
        self.mock_git.tag_exists.return_value = False
        self.mock_gh.get_release_tracking_issue.side_effect = NoTrackingIssueError(
            "Not found"
        )

        # Act
        result = PromoteRc(args, self.mock_git, self.mock_gh).run()

        # Assert
        self.assertEqual(result, 1)
        self.mock_gh.get_release_tracking_issue.assert_called_once_with("2.0.0")
        self.mock_git.checkout.assert_not_called()
        self.mock_git.tag.assert_not_called()
        self.mock_git.push.assert_not_called()
        self.mock_gh.get_issue_body.assert_not_called()

    def test_promote_rc_issue_malformed(self):
        # Arrange
        args = argparse.Namespace(
            version="2.0.0", issue=123, dry_run=False, remote="my-remote"
        )
        self.mock_git.get_remote_tags.return_value = ["2.0.0-rc1"]
        self.mock_git.tag_exists.return_value = False
        self.mock_git.get_commit_sha.return_value = "abcdef123456"
        initial_body = "malformed body"
        self.mock_gh.get_issue_body.return_value = initial_body

        # Act
        result = PromoteRc(args, self.mock_git, self.mock_gh).run()

        # Assert
        self.assertEqual(result, 1)
        self.mock_gh.get_issue_body.assert_called_once_with(123)
        self.mock_git.checkout.assert_not_called()
        self.mock_git.tag.assert_not_called()
        self.mock_git.push.assert_not_called()
        self.mock_gh.update_issue_body.assert_not_called()

    def test_promote_rc_no_rc_found(self):
        # Arrange
        args = argparse.Namespace(
            version="2.0.0", issue=123, dry_run=False, remote="my-remote"
        )
        self.mock_git.get_remote_tags.return_value = []

        # Act
        result = PromoteRc(args, self.mock_git, self.mock_gh).run()

        # Assert
        self.assertEqual(result, 1)
        self.mock_git.checkout.assert_not_called()
        self.mock_git.tag.assert_not_called()
        self.mock_gh.get_issue_body.assert_not_called()


if __name__ == "__main__":
    unittest.main()
