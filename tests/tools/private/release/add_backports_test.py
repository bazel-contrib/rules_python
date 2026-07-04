import argparse
import unittest
from unittest.mock import patch

from tests.tools.private.release.release_test_helper import _mock_git_and_gh
from tools.private.release.add_backports import AddBackports


class CmdAddBackportsTest(unittest.TestCase):
    def setUp(self):
        _mock_git_and_gh(self)
        self.addCleanup(patch.stopall)
        self.mock_gh.resolve_pr_number.side_effect = lambda x: int(
            x.lstrip("#").split("/")[-1]
        )

    def test_add_backports_explicit_issue(self):
        args = argparse.Namespace(issue=123, prs=["124", "125"])
        self.mock_gh.get_issue_body.return_value = """
## Checklist
- [ ] Prepare Release
- [ ] Create Release branch
- [ ] Tag Final

## Backports
"""
        result = AddBackports(args, self.mock_gh).run()

        self.assertEqual(result, 0)
        self.mock_gh.get_issue_body.assert_called_once_with(123)
        self.mock_gh.update_issue_body.assert_called_once()
        call_args = self.mock_gh.update_issue_body.call_args[0]
        self.assertEqual(call_args[0], 123)
        self.assertIn("- [ ] #124", call_args[1])
        self.assertIn("- [ ] #125", call_args[1])
        # Should also auto-add Tag RC0
        self.assertIn("- [ ] Tag RC0", call_args[1])

    def test_add_backports_auto_discover_success(self):
        args = argparse.Namespace(issue=None, prs=["124"])
        self.mock_gh.get_open_tracking_issues.return_value = [
            {"number": 456, "title": "Release 2.1.0", "url": "http://..."}
        ]
        self.mock_gh.get_issue_body.return_value = """
## Checklist
- [ ] Prepare Release
- [ ] Create Release branch
- [ ] Tag Final

## Backports
"""
        result = AddBackports(args, self.mock_gh).run()

        self.assertEqual(result, 0)
        self.mock_gh.get_open_tracking_issues.assert_called_once()
        self.mock_gh.get_issue_body.assert_called_once_with(456)
        self.mock_gh.update_issue_body.assert_called_once_with(456, unittest.mock.ANY)

    def test_add_backports_auto_discover_no_issues(self):
        args = argparse.Namespace(issue=None, prs=["124"])
        self.mock_gh.get_open_tracking_issues.return_value = []

        result = AddBackports(args, self.mock_gh).run()

        self.assertEqual(result, 1)
        self.mock_gh.get_open_tracking_issues.assert_called_once()
        self.mock_gh.get_issue_body.assert_not_called()

    def test_add_backports_auto_discover_multiple_issues(self):
        args = argparse.Namespace(issue=None, prs=["124"])
        self.mock_gh.get_open_tracking_issues.return_value = [
            {"number": 456, "title": "Release 2.1.0", "url": "http://..."},
            {"number": 789, "title": "Release 2.2.0", "url": "http://..."},
        ]

        result = AddBackports(args, self.mock_gh).run()

        self.assertEqual(result, 1)
        self.mock_gh.get_open_tracking_issues.assert_called_once()
        self.mock_gh.get_issue_body.assert_not_called()

    def test_add_backports_no_auto_add_rc_if_pending(self):
        args = argparse.Namespace(issue=123, prs=["124"])
        self.mock_gh.get_issue_body.return_value = """
## Checklist
- [ ] Prepare Release
- [ ] Create Release branch
- [ ] Tag RC0
- [ ] Tag Final

## Backports
"""
        result = AddBackports(args, self.mock_gh).run()

        self.assertEqual(result, 0)
        self.mock_gh.update_issue_body.assert_called_once()
        call_args = self.mock_gh.update_issue_body.call_args[0]
        self.assertNotIn("Tag RC1", call_args[1])
        # Tag RC0 should still be there
        self.assertIn("- [ ] Tag RC0", call_args[1])


if __name__ == "__main__":
    unittest.main()
