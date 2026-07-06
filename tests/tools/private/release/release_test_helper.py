import os
import pathlib
import shutil
import tempfile
import unittest
from unittest.mock import MagicMock, patch

from tools.private.release.gh import (
    MultipleTrackingIssuesError,
    NoTrackingIssueError,
)


def _mock_git_and_gh(test_case):
    mock_git = MagicMock()
    mock_gh = MagicMock()
    test_case.mock_git = mock_git
    test_case.mock_gh = mock_gh

    # Mock Git inside utils.py since it instantiates it locally
    patch("tools.private.release.utils.Git", return_value=mock_git).start()

    mock_gh.MultipleTrackingIssuesError = MultipleTrackingIssuesError
    mock_gh.NoTrackingIssueError = NoTrackingIssueError

    test_case.addCleanup(patch.stopall)

    # Apply safe defaults
    mock_git.get_current_branch.return_value = None
    mock_git.get_tags.return_value = []
    mock_git.get_remote_tags.return_value = []

    mock_git.status.return_value = ""
    mock_git.branch_exists.return_value = False
    mock_git.tag_exists.return_value = False
    mock_gh.get_release_tracking_issue.side_effect = NoTrackingIssueError("Not found")
    mock_gh.get_open_pr.return_value = None


class TempDirTestCase(unittest.TestCase):
    def setUp(self):
        self.tmpdir = pathlib.Path(tempfile.mkdtemp())
        self.original_cwd = os.getcwd()
        self.addCleanup(shutil.rmtree, self.tmpdir)
        os.chdir(self.tmpdir)
        self.addCleanup(os.chdir, self.original_cwd)
