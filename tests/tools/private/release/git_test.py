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
        mock_reset_hard.assert_called_once_with(reset_to="origin/my-branch")


class GitFetchTest(unittest.TestCase):
    def setUp(self):
        self.git = Git(".")
        self.patcher = patch.object(self.git, "_run_git")
        self.mock_run_git = self.patcher.start()
        self.addCleanup(self.patcher.stop)

    def test_fetch_default(self):
        self.git.fetch()
        self.mock_run_git.assert_called_once_with(
            "fetch", "origin", capture_output=False
        )

    def test_fetch_custom_remote(self):
        self.git.fetch("upstream")
        self.mock_run_git.assert_called_once_with(
            "fetch", "upstream", capture_output=False
        )

    def test_fetch_with_refspec(self):
        self.git.fetch("origin", refspec="my-branch")
        self.mock_run_git.assert_called_once_with(
            "fetch", "origin", "my-branch", capture_output=False
        )

    def test_fetch_with_tags_and_force(self):
        self.git.fetch("origin", tags=True, force=True)
        self.mock_run_git.assert_called_once_with(
            "fetch", "origin", "--tags", "--force", capture_output=False
        )

    def test_fetch_all_options(self):
        self.git.fetch("origin", refspec="my-branch", tags=True, force=True)
        self.mock_run_git.assert_called_once_with(
            "fetch", "origin", "my-branch", "--tags", "--force", capture_output=False
        )


class GitGetModifiedFilesTest(unittest.TestCase):
    def setUp(self):
        self.git = Git(".")
        self.patcher = patch.object(self.git, "_run_git")
        self.mock_run_git = self.patcher.start()
        self.addCleanup(self.patcher.stop)

    def test_get_modified_files(self):
        self.mock_run_git.return_value = "file1.txt\nfile2.py\n\n"
        files = self.git.get_modified_files("HEAD")
        self.mock_run_git.assert_called_once_with(
            "show", "--name-only", "--format=", "HEAD"
        )
        self.assertEqual(files, ["file1.txt", "file2.py"])

    def test_get_modified_files_empty(self):
        self.mock_run_git.return_value = ""
        files = self.git.get_modified_files("HEAD")
        self.assertEqual(files, [])


class GitDiffTest(unittest.TestCase):
    def setUp(self):
        self.git = Git(".")
        self.patcher = patch.object(self.git, "_run_git")
        self.mock_run_git = self.patcher.start()
        self.addCleanup(self.patcher.stop)

    def test_diff_has_changes(self):
        self.mock_run_git.return_value = "some diff output"
        output = self.git.diff()
        self.mock_run_git.assert_called_once_with("diff")
        self.assertEqual(output, "some diff output")

    def test_diff_empty(self):
        self.mock_run_git.return_value = ""
        output = self.git.diff()
        self.mock_run_git.assert_called_once_with("diff")
        self.assertEqual(output, "")


class GitApplyTest(unittest.TestCase):
    def setUp(self):
        self.git = Git(".")
        self.patcher = patch.object(self.git, "_run_git")
        self.mock_run_git = self.patcher.start()
        self.addCleanup(self.patcher.stop)

    def test_apply(self):
        self.git.apply("patch.patch")
        self.mock_run_git.assert_called_once_with(
            "apply", "patch.patch", capture_output=False
        )


class GitApplyCheckTest(unittest.TestCase):
    def setUp(self):
        self.git = Git(".")
        self.patcher = patch.object(self.git, "_run_git")
        self.mock_run_git = self.patcher.start()
        self.addCleanup(self.patcher.stop)

    def test_apply_check_clean(self):
        self.mock_run_git.return_value = ""
        result = self.git.apply_check("patch.patch")
        self.mock_run_git.assert_called_once_with(
            "apply", "--check", "patch.patch", capture_output=False
        )
        self.assertTrue(result)

    def test_apply_check_conflict(self):
        import subprocess

        self.mock_run_git.side_effect = subprocess.CalledProcessError(
            1, ["git", "apply", "--check", "patch.patch"]
        )
        result = self.git.apply_check("patch.patch")
        self.mock_run_git.assert_called_once_with(
            "apply", "--check", "patch.patch", capture_output=False
        )
        self.assertFalse(result)


class GitResetHardTest(unittest.TestCase):
    def setUp(self):
        self.git = Git(".")
        self.patcher = patch.object(self.git, "_run_git")
        self.mock_run_git = self.patcher.start()
        self.addCleanup(self.patcher.stop)

    def test_reset_hard_default(self):
        self.git.reset_hard()
        self.mock_run_git.assert_called_once_with(
            "reset", "--hard", "HEAD", capture_output=False
        )

    def test_reset_hard_custom(self):
        self.git.reset_hard(reset_to="my-commit")
        self.mock_run_git.assert_called_once_with(
            "reset", "--hard", "my-commit", capture_output=False
        )


if __name__ == "__main__":
    unittest.main()
