import argparse
import unittest
from unittest.mock import patch

from tests.tools.private.release.release_test_helper import _mock_git_and_gh
from tools.private.release.complete_sync_changelog import CompleteSyncChangelog


class CompleteSyncChangelogTest(unittest.TestCase):
    def setUp(self):
        _mock_git_and_gh(self)
        self.addCleanup(patch.stopall)

        # Dynamic mock for issue body
        self.issue_body = ""

        def mock_get_body(issue_num):
            return self.issue_body

        def mock_update_body(issue_num, body):
            self.issue_body = body

        self.mock_gh.get_issue_body.side_effect = mock_get_body
        self.mock_gh.update_issue_body.side_effect = mock_update_body

    def test_complete_sync_changelog_success(self):
        args = argparse.Namespace(pr=999)
        self.mock_gh.get_pr_info.return_value = {
            "state": "MERGED",
            "body": "Updates CHANGELOG.md\n\nRelease-Tracking-Issue: #123",
            "mergeCommit": {"oid": "abcdef1234567890"},
        }
        self.issue_body = """
## Checklist
- [ ] Prepare Release
- [ ] Create Release branch
- [ ] Sync Changelog #124 | status=pending pr=#999
- [ ] Sync Changelog #125 | status=pending pr=#999
- [ ] Sync Changelog #126 | status=pending pr=#888
- [ ] Tag Final

## Backports
"""
        result = CompleteSyncChangelog(args, self.mock_gh).run()

        self.assertEqual(result, 0)
        self.mock_gh.get_pr_info.assert_called_once_with(999)
        self.mock_gh.get_issue_body.assert_called_once_with(123)
        self.mock_gh.update_issue_body.assert_called_once()

        # Check that only tasks pointing to #999 were marked checked=True and status=done
        self.assertIn(
            "- [x] Sync Changelog #124 | status=done pr=#999 commit= abcdef12",
            self.issue_body,
        )
        self.assertIn(
            "- [x] Sync Changelog #125 | status=done pr=#999 commit= abcdef12",
            self.issue_body,
        )
        # Task pointing to #888 should remain unchanged
        self.assertIn(
            "- [ ] Sync Changelog #126 | status=pending pr=#888",
            self.issue_body,
        )

    def test_complete_sync_changelog_not_merged(self):
        args = argparse.Namespace(pr=999)
        self.mock_gh.get_pr_info.return_value = {
            "state": "OPEN",
            "body": "Updates CHANGELOG.md\n\nRelease-Tracking-Issue: #123",
        }

        result = CompleteSyncChangelog(args, self.mock_gh).run()

        self.assertEqual(result, 1)
        self.mock_gh.get_pr_info.assert_called_once_with(999)
        self.mock_gh.update_issue_body.assert_not_called()

    def test_complete_sync_changelog_missing_tracking_issue_link(self):
        args = argparse.Namespace(pr=999)
        self.mock_gh.get_pr_info.return_value = {
            "state": "MERGED",
            "body": "Updates CHANGELOG.md without tracking issue link",
            "mergeCommit": {"oid": "abcdef1234567890"},
        }

        result = CompleteSyncChangelog(args, self.mock_gh).run()

        self.assertEqual(result, 1)
        self.mock_gh.get_pr_info.assert_called_once_with(999)
        self.mock_gh.update_issue_body.assert_not_called()

    def test_complete_sync_changelog_no_matching_tasks(self):
        args = argparse.Namespace(pr=999)
        self.mock_gh.get_pr_info.return_value = {
            "state": "MERGED",
            "body": "Updates CHANGELOG.md\n\nRelease-Tracking-Issue: #123",
            "mergeCommit": {"oid": "abcdef1234567890"},
        }
        # Checklist has no tasks pointing to #999
        self.issue_body = """
## Checklist
- [ ] Prepare Release
- [ ] Create Release branch
- [ ] Sync Changelog #124 | status=pending pr=#888
- [ ] Tag Final

## Backports
"""
        result = CompleteSyncChangelog(args, self.mock_gh).run()

        # Should log warning but return 0 (success/noop)
        self.assertEqual(result, 0)
        self.mock_gh.get_pr_info.assert_called_once_with(999)
        self.mock_gh.get_issue_body.assert_called_once_with(123)
        self.mock_gh.update_issue_body.assert_not_called()


if __name__ == "__main__":
    unittest.main()
