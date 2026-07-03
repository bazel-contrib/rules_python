import argparse
import os
import tempfile
import unittest
from unittest.mock import patch

from tests.tools.private.release.release_test_helper import _mock_git_and_gh
from tools.private.release.find_release_issue import FindReleaseIssue


class CmdFindReleaseIssueTest(unittest.TestCase):
    def setUp(self):
        _mock_git_and_gh(self)
        self.addCleanup(patch.stopall)

    def test_find_release_issue_success(self):
        args = argparse.Namespace(pr=124)
        self.mock_gh.get_open_tracking_issues.return_value = [
            {"number": 456, "title": "Release 2.1.0", "url": "http://..."}
        ]
        self.mock_gh.get_issue_body.return_value = """
## Checklist
- [ ] Prepare Release

## Backports
- [ ] #124 | status=pending
"""
        result = FindReleaseIssue(args, self.mock_gh).run()

        self.assertEqual(result, 0)
        self.mock_gh.get_open_tracking_issues.assert_called_once()
        self.mock_gh.get_issue_body.assert_called_once_with(456)

    def test_find_release_issue_not_found(self):
        args = argparse.Namespace(pr=124)
        self.mock_gh.get_open_tracking_issues.return_value = [
            {"number": 456, "title": "Release 2.1.0", "url": "http://..."}
        ]
        self.mock_gh.get_issue_body.return_value = """
## Checklist
- [ ] Prepare Release

## Backports
- [ ] #125 | status=pending
"""
        result = FindReleaseIssue(args, self.mock_gh).run()

        self.assertEqual(result, 1)
        self.mock_gh.get_open_tracking_issues.assert_called_once()
        self.mock_gh.get_issue_body.assert_called_once_with(456)

    def test_find_release_issue_multiple_issues(self):
        args = argparse.Namespace(pr=124)
        self.mock_gh.get_open_tracking_issues.return_value = [
            {"number": 456, "title": "Release 2.1.0", "url": "http://..."},
            {"number": 789, "title": "Release 2.2.0", "url": "http://..."},
        ]
        self.mock_gh.get_issue_body.side_effect = [
            """
## Backports
- [ ] #124 | status=pending
""",
            """
## Backports
- [ ] #124 | status=pending
""",
        ]

        result = FindReleaseIssue(args, self.mock_gh).run()

        self.assertEqual(result, 1)
        self.mock_gh.get_open_tracking_issues.assert_called_once()
        self.assertEqual(self.mock_gh.get_issue_body.call_count, 2)

    def test_find_release_issue_no_active_releases(self):
        args = argparse.Namespace(pr=124)
        self.mock_gh.get_open_tracking_issues.return_value = []

        result = FindReleaseIssue(args, self.mock_gh).run()

        self.assertEqual(result, 1)
        self.mock_gh.get_open_tracking_issues.assert_called_once()
        self.mock_gh.get_issue_body.assert_not_called()

    def test_find_release_issue_github_output(self):
        args = argparse.Namespace(pr=124)
        self.mock_gh.get_open_tracking_issues.return_value = [
            {"number": 456, "title": "Release 2.1.0", "url": "http://..."}
        ]
        self.mock_gh.get_issue_body.return_value = """
## Backports
- [ ] #124 | status=pending
"""
        with tempfile.NamedTemporaryFile(mode="w+", delete=False) as tmp:
            tmp_path = tmp.name

        try:
            with patch.dict(os.environ, {"GITHUB_OUTPUT": tmp_path}):
                result = FindReleaseIssue(args, self.mock_gh).run()

            self.assertEqual(result, 0)
            with open(tmp_path, "r") as f:
                content = f.read()
            self.assertEqual(content, "issue=456\n")
        finally:
            if os.path.exists(tmp_path):
                os.unlink(tmp_path)


if __name__ == "__main__":
    unittest.main()
