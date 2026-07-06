import unittest
from unittest.mock import MagicMock

from tests.tools.private.release.release_test_helper import _mock_git_and_gh
from tools.private.release.create_release_branch import CreateReleaseBranch


class CmdCreateReleaseBranchTest(unittest.TestCase):
    def setUp(self):
        _mock_git_and_gh(self)

    def test_create_release_branch_success(self):
        # Arrange
        args = MagicMock(issue=123, remote="my-remote")
        self.mock_gh.get_issue_title.return_value = "Release 2.0.0"
        self.mock_gh.get_issue_body.return_value = """
## Checklist
- [x] Prepare Release | status=done pr=#122 commit=abcdef12
- [ ] Create Release branch | status=pending
"""
        self.mock_git.branch_exists.return_value = False
        self.mock_git.remote_branch_exists.return_value = False

        # Act
        result = CreateReleaseBranch(args, self.mock_git, self.mock_gh).run()

        # Assert
        self.assertEqual(result, 0)
        self.mock_git.fetch.assert_called_once_with("my-remote")
        self.mock_git.checkout.assert_not_called()
        self.mock_git.push.assert_called_once_with(
            "my-remote", "abcdef12:refs/heads/release/2.0"
        )

        self.mock_gh.update_issue_body.assert_called_once()
        call_args = self.mock_gh.update_issue_body.call_args[0]
        self.assertEqual(call_args[0], 123)
        self.assertIn(
            "branch_url=https://github.com/bazel-contrib/rules_python/tree/release/2.0",
            call_args[1],
        )
        self.assertIn("commit= abcdef12", call_args[1])

    def test_create_release_branch_prepare_not_done(self):
        # Arrange
        args = MagicMock(issue=123, remote="my-remote")
        self.mock_gh.get_issue_title.return_value = "Release 2.0.0"
        self.mock_gh.get_issue_body.return_value = """
## Checklist
- [ ] Prepare Release | status=pending
- [ ] Create Release branch | status=pending
"""
        # Act
        result = CreateReleaseBranch(args, self.mock_git, self.mock_gh).run()

        # Assert
        self.assertEqual(result, 1)
        self.mock_git.fetch.assert_not_called()
        self.mock_git.push.assert_not_called()
        self.mock_gh.update_issue_body.assert_not_called()

    def test_create_release_branch_already_checked(self):
        # Arrange
        args = MagicMock(issue=123, remote="my-remote")
        self.mock_gh.get_issue_title.return_value = "Release 2.0.0"
        self.mock_gh.get_issue_body.return_value = """
## Checklist
- [x] Prepare Release | status=done pr=#122 commit=abcdef12
- [x] Create Release branch | status=done branch=release/2.0 commit=abcdef12
"""
        # Act
        result = CreateReleaseBranch(args, self.mock_git, self.mock_gh).run()

        # Assert
        self.assertEqual(result, 0)
        self.mock_git.fetch.assert_not_called()
        self.mock_git.push.assert_not_called()
        self.mock_gh.update_issue_body.assert_not_called()

    def test_create_release_branch_already_exists_same_commit(self):
        # Arrange
        args = MagicMock(issue=123, remote="my-remote")
        self.mock_gh.get_issue_title.return_value = "Release 2.0.0"
        self.mock_gh.get_issue_body.return_value = """
## Checklist
- [x] Prepare Release | status=done pr=#122 commit=abcdef12
- [ ] Create Release branch | status=pending
"""
        self.mock_git.remote_branch_exists.return_value = True
        self.mock_git.get_commit_sha.return_value = "abcdef12"

        # Act
        result = CreateReleaseBranch(args, self.mock_git, self.mock_gh).run()

        # Assert
        self.assertEqual(result, 0)
        self.mock_git.fetch.assert_called_once_with("my-remote")
        self.mock_git.push.assert_not_called()
        self.mock_gh.update_issue_body.assert_called_once()  # Should still update checklist

    def test_create_release_branch_already_exists_fast_forward(self):
        # Arrange
        args = MagicMock(issue=123, remote="my-remote")
        self.mock_gh.get_issue_title.return_value = "Release 2.0.0"
        self.mock_gh.get_issue_body.return_value = """
## Checklist
- [x] Prepare Release | status=done pr=#122 commit=abcdef12
- [ ] Create Release branch | status=pending
"""
        self.mock_git.remote_branch_exists.return_value = True
        self.mock_git.get_commit_sha.return_value = "oldcommit"
        self.mock_git.is_ancestor.return_value = True

        # Act
        result = CreateReleaseBranch(args, self.mock_git, self.mock_gh).run()

        # Assert
        self.assertEqual(result, 0)
        self.mock_git.fetch.assert_called_once_with("my-remote")
        self.mock_git.push.assert_called_once_with(
            "my-remote", "abcdef12:refs/heads/release/2.0"
        )
        self.mock_gh.update_issue_body.assert_called_once()

    def test_create_release_branch_already_exists_non_ff(self):
        # Arrange
        args = MagicMock(issue=123, remote="my-remote")
        self.mock_gh.get_issue_title.return_value = "Release 2.0.0"
        self.mock_gh.get_issue_body.return_value = """
## Checklist
- [x] Prepare Release | status=done pr=#122 commit=abcdef12
- [ ] Create Release branch | status=pending
"""
        self.mock_git.remote_branch_exists.return_value = True
        self.mock_git.get_commit_sha.return_value = "othercommit"
        self.mock_git.is_ancestor.return_value = False

        # Act
        result = CreateReleaseBranch(args, self.mock_git, self.mock_gh).run()

        # Assert
        self.assertEqual(result, 1)
        self.mock_git.fetch.assert_called_once_with("my-remote")
        self.mock_git.push.assert_not_called()
        self.mock_gh.update_issue_body.assert_not_called()


if __name__ == "__main__":
    unittest.main()
