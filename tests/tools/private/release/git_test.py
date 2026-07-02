import unittest
from unittest.mock import patch

from tools.private.release.git import Git


class GitCheckoutTest(unittest.TestCase):
    def setUp(self):
        self.git = Git(".")
        self.patcher = patch.object(self.git, "_run_git")
        self.mock_run_git = self.patcher.start()
        self.addCleanup(self.patcher.stop)

    def test_checkout_simple(self):
        self.git.checkout("my-branch")
        self.mock_run_git.assert_called_once_with(
            "checkout", "my-branch", capture_output=False
        )

    @patch("tools.private.release.git.Git.branch_exists")
    def test_checkout_track_remote_new_branch(self, mock_branch_exists):
        mock_branch_exists.return_value = False

        self.git.checkout("my-branch", track_remote="origin")

        mock_branch_exists.assert_called_once_with("my-branch")
        self.mock_run_git.assert_called_once_with(
            "checkout", "--track", "origin/my-branch", capture_output=False
        )

    @patch("tools.private.release.git.Git.reset_hard")
    @patch("tools.private.release.git.Git.branch_exists")
    def test_checkout_track_remote_existing_branch(
        self, mock_branch_exists, mock_reset_hard
    ):
        mock_branch_exists.return_value = True

        self.git.checkout("my-branch", track_remote="origin")

        mock_branch_exists.assert_called_once_with("my-branch")
        self.mock_run_git.assert_called_once_with(
            "checkout", "my-branch", capture_output=False
        )
        mock_reset_hard.assert_called_once_with("origin/my-branch")


if __name__ == "__main__":
    unittest.main()
