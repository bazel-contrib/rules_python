import argparse
import unittest
from unittest.mock import MagicMock, patch

from tests.tools.private.release.release_test_helper import _mock_git_and_gh
from tools.private.release.on_pr_merged import OnPrMerged


class CmdOnPrMergedTest(unittest.TestCase):
    def setUp(self):
        _mock_git_and_gh(self)
        self.addCleanup(patch.stopall)

        # Mock ProcessBackports
        self.mock_process_patcher = patch(
            "tools.private.release.on_pr_merged.ProcessBackports"
        )
        self.mock_process_class = self.mock_process_patcher.start()
        self.mock_process_instance = MagicMock()
        self.mock_process_class.return_value = self.mock_process_instance

    def test_on_pr_merged_no_comment(self):
        args = argparse.Namespace(pr=124, remote="origin", dry_run=True)
        self.mock_gh.get_pr_comments.return_value = [
            {"body": "Some comment"},
            {"body": "Another comment /backport_wrong"},
        ]

        result = OnPrMerged(args, self.mock_git, self.mock_gh).run()

        self.assertEqual(result, 1)
        self.mock_gh.get_pr_comments.assert_called_once_with(124)
        self.mock_gh.get_open_tracking_issues.assert_not_called()
        self.mock_process_class.assert_not_called()

    def test_on_pr_merged_has_comment_no_active_release(self):
        args = argparse.Namespace(pr=124, remote="origin", dry_run=True)
        self.mock_gh.get_pr_comments.return_value = [
            {"body": "/backport"},
        ]
        self.mock_gh.get_open_tracking_issues.return_value = []

        result = OnPrMerged(args, self.mock_git, self.mock_gh).run()

        self.assertEqual(result, 1)
        self.mock_gh.get_pr_comments.assert_called_once_with(124)
        self.mock_gh.get_open_tracking_issues.assert_called_once()
        self.mock_gh.get_issue_body.assert_not_called()
        self.mock_process_class.assert_not_called()

    def test_on_pr_merged_has_comment_not_in_backports(self):
        args = argparse.Namespace(pr=124, remote="origin", dry_run=True)
        self.mock_gh.get_pr_comments.return_value = [
            {"body": "  /backport  "},
        ]
        self.mock_gh.get_open_tracking_issues.return_value = [
            {"number": 456, "title": "Release 2.1.0", "url": "http://..."}
        ]
        self.mock_gh.get_issue_body.return_value = """
## Checklist
- [ ] Prepare Release

## Backports
- [ ] #125 | status=pending
"""
        result = OnPrMerged(args, self.mock_git, self.mock_gh).run()

        self.assertEqual(result, 1)
        self.mock_gh.get_pr_comments.assert_called_once_with(124)
        self.mock_gh.get_open_tracking_issues.assert_called_once()
        self.mock_gh.get_issue_body.assert_called_once_with(456)
        self.mock_process_class.assert_not_called()

    def test_on_pr_merged_success(self):
        args = argparse.Namespace(pr=124, remote="origin", dry_run=True)
        self.mock_gh.get_pr_comments.return_value = [
            {"body": "/backport"},
        ]
        self.mock_gh.get_open_tracking_issues.return_value = [
            {"number": 456, "title": "Release 2.1.0", "url": "http://..."}
        ]
        self.mock_gh.get_issue_body.return_value = """
## Checklist
- [ ] Prepare Release

## Backports
- [ ] #124 | status=pending
"""
        self.mock_process_instance.run.return_value = 0

        result = OnPrMerged(args, self.mock_git, self.mock_gh).run()

        self.assertEqual(result, 0)
        self.mock_gh.get_pr_comments.assert_called_once_with(124)
        self.mock_gh.get_open_tracking_issues.assert_called_once()
        self.mock_gh.get_issue_body.assert_called_once_with(456)

        # Verify ProcessBackports was instantiated with correct args
        self.mock_process_class.assert_called_once()
        called_args = self.mock_process_class.call_args[0][0]
        self.assertEqual(called_args.issue, 456)
        self.assertEqual(called_args.remote, "origin")
        self.assertEqual(called_args.dry_run, True)
        self.assertIsNone(called_args.add)
        self.assertIsNone(called_args.triggering_comment)

        # Verify ProcessBackports.run() was called
        self.mock_process_instance.run.assert_called_once()


if __name__ == "__main__":
    unittest.main()
