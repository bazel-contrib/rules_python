import argparse
import datetime
import unittest
from unittest.mock import call, patch

from tests.tools.private.release.release_test_helper import _mock_git_and_gh
from tools.private.release.process_backports import ProcessBackports


class CmdProcessBackportsTest(unittest.TestCase):
    def setUp(self):
        _mock_git_and_gh(self)
        self.mock_changelog_news = patch(
            "tools.private.release.process_backports.changelog_news"
        ).start()
        self.mock_replace_version_next = patch(
            "tools.private.release.process_backports.replace_version_next"
        ).start()
        self.addCleanup(patch.stopall)

    def test_process_backports_no_pending(self):
        args = argparse.Namespace(
            issue=123, remote="origin", dry_run=False, add=None, triggering_comment=None
        )
        self.mock_gh.get_issue_body.return_value = "No backports here"

        result = ProcessBackports(args, self.mock_git, self.mock_gh).run()

        self.assertEqual(result, 0)
        self.mock_gh.get_issue_body.assert_called_once_with(123)
        self.mock_git.fetch.assert_not_called()

    @patch("tools.private.release.process_backports.datetime")
    def test_process_backports_success(self, mock_datetime):
        mock_datetime.date.today.return_value = datetime.date(2026, 7, 1)
        args = argparse.Namespace(
            issue=123, remote="origin", dry_run=False, add=None, triggering_comment=None
        )
        self.mock_gh.get_issue_title.return_value = "Release 2.0.0"
        self.mock_gh.get_issue_body.return_value = """
## Checklist
- [ ] Prepare Release
- [ ] Create Release branch

## Backports
- [ ] #124 | status=pending
"""
        self.mock_git.get_remote_tags.return_value = []

        def mock_resolve(items):
            for item in items:
                if item.pr_ref == "#124":
                    item.commit = "abcdef12"
                    item.status = "done"
            return items

        self.mock_gh.get_merge_commits_for_prs.side_effect = mock_resolve

        self.mock_git.sort_commits_chronologically.return_value = ["abcdef12"]
        self.mock_git.get_commit_sha.return_value = "12345678"
        self.mock_git.get_commit_message.return_value = 'Cherry-pick "fix bug"'

        result = ProcessBackports(args, self.mock_git, self.mock_gh).run()

        self.assertEqual(result, 0)
        self.mock_git.fetch.assert_has_calls(
            [call("origin", tags=True, force=True), call("origin")]
        )
        self.mock_git.checkout.assert_called_once_with(
            "release/2.0", track_remote="origin"
        )
        self.mock_git.cherry_pick.assert_called_once_with("abcdef12")
        self.mock_changelog_news.update_changelog.assert_called_once_with(
            "2.0.0", "2026-07-01"
        )
        self.mock_git.add_modified_and_deleted.assert_called_once()
        self.mock_replace_version_next.assert_called_once_with("2.0.0")
        self.mock_git.commit.assert_called_once_with(
            'Cherry-pick "fix bug"\n\nWork towards #123', amend=True
        )
        self.mock_git.push.assert_called_once_with("origin", "release/2.0")

        self.mock_gh.update_issue_body.assert_called_once()
        call_args = self.mock_gh.update_issue_body.call_args[0]
        self.assertEqual(call_args[0], 123)
        self.assertIn("- [x] #124 | status=done rc=rc0 commit= 12345678", call_args[1])

    @patch("tools.private.release.process_backports.datetime")
    def test_process_backports_dry_run(self, mock_datetime):
        mock_datetime.date.today.return_value = datetime.date(2026, 7, 1)
        args = argparse.Namespace(
            issue=123, remote="origin", dry_run=True, add=None, triggering_comment=None
        )
        self.mock_gh.get_issue_title.return_value = "Release 2.0.0"
        self.mock_gh.get_issue_body.return_value = """
## Checklist
- [ ] Prepare Release
- [ ] Create Release branch

## Backports
- [ ] #124 | status=pending
"""
        self.mock_git.get_remote_tags.return_value = []

        def mock_resolve(items):
            for item in items:
                if item.pr_ref == "#124":
                    item.commit = "abcdef12"
                    item.status = "done"
            return items

        self.mock_gh.get_merge_commits_for_prs.side_effect = mock_resolve

        self.mock_git.sort_commits_chronologically.return_value = ["abcdef12"]
        self.mock_git.get_commit_sha.return_value = "12345678"
        self.mock_git.get_commit_message.return_value = 'Cherry-pick "fix bug"'

        result = ProcessBackports(args, self.mock_git, self.mock_gh).run()

        self.assertEqual(result, 0)
        self.mock_git.fetch.assert_has_calls(
            [call("origin", tags=True, force=True), call("origin")]
        )
        self.mock_git.checkout.assert_called_once_with(
            "release/2.0", track_remote="origin"
        )
        self.mock_git.cherry_pick.assert_called_once_with("abcdef12")
        self.mock_changelog_news.update_changelog.assert_called_once_with(
            "2.0.0", "2026-07-01"
        )
        self.mock_git.add_modified_and_deleted.assert_called_once()
        self.mock_replace_version_next.assert_called_once_with("2.0.0")
        self.mock_git.commit.assert_called_once_with(
            'Cherry-pick "fix bug"\n\nWork towards #123', amend=True
        )
        self.mock_git.reset_hard.assert_called_once_with("12345678")
        self.mock_git.push.assert_not_called()
        self.mock_gh.update_issue_body.assert_not_called()

    def test_process_backports_ignored_and_failed_states(self):
        args = argparse.Namespace(
            issue=123, remote="origin", dry_run=False, add=None, triggering_comment=None
        )
        self.mock_gh.get_issue_title.return_value = "Release 2.0.0"
        self.mock_gh.get_issue_body.return_value = """
## Checklist
- [ ] Prepare Release
- [ ] Create Release branch

## Backports
- [ ] #124 | status=pending
- [ ] #125 | status=pending
- [ ] #126 | status=pending
"""
        self.mock_git.get_remote_tags.return_value = []

        def mock_resolve(items):
            for item in items:
                if item.pr_ref == "#124":
                    item.status = "open-pr"
                elif item.pr_ref == "#125":
                    item.status = "draft-pr"
                elif item.pr_ref == "#126":
                    item.status = "error-closed-pr"
            return items

        self.mock_gh.get_merge_commits_for_prs.side_effect = mock_resolve

        result = ProcessBackports(args, self.mock_git, self.mock_gh).run()

        self.assertEqual(result, 1)
        self.mock_gh.update_issue_body.assert_called_once()
        call_args = self.mock_gh.update_issue_body.call_args[0]
        self.assertEqual(call_args[0], 123)
        self.assertIn("- [ ] #126 | status=error-closed-pr", call_args[1])
        self.assertNotIn("status=open-pr", call_args[1])
        self.assertNotIn("status=draft-pr", call_args[1])
        self.mock_git.checkout.assert_not_called()
        self.mock_git.cherry_pick.assert_not_called()

    def test_process_backports_ignored_error_status(self):
        args = argparse.Namespace(
            issue=123, remote="origin", dry_run=False, add=None, triggering_comment=None
        )
        self.mock_gh.get_issue_title.return_value = "Release 2.0.0"
        self.mock_gh.get_issue_body.return_value = """
## Checklist
- [ ] Prepare Release
- [ ] Create Release branch

## Backports
- [ ] #124 | status=error-merge-conflict
- [ ] #125 | status=error-some-other-error
"""
        self.mock_git.get_remote_tags.return_value = []
        self.mock_gh.get_merge_commits_for_prs.return_value = []

        result = ProcessBackports(args, self.mock_git, self.mock_gh).run()

        self.assertEqual(result, 0)
        self.mock_gh.get_merge_commits_for_prs.assert_not_called()
        self.mock_git.checkout.assert_not_called()

    @patch("tools.private.release.process_backports.datetime")
    def test_process_backports_cherry_pick_failed(self, mock_datetime):
        mock_datetime.date.today.return_value = datetime.date(2026, 7, 1)
        args = argparse.Namespace(
            issue=123, remote="origin", dry_run=False, add=None, triggering_comment=None
        )
        self.mock_gh.get_issue_title.return_value = "Release 2.0.0"
        self.mock_gh.get_issue_body.return_value = """
## Checklist
- [ ] Prepare Release
- [ ] Create Release branch

## Backports
- [ ] #124 | status=pending
"""
        self.mock_git.get_remote_tags.return_value = []

        def mock_resolve(items):
            for item in items:
                if item.pr_ref == "#124":
                    item.commit = "abcdef12"
                    item.status = "done"
            return items

        self.mock_gh.get_merge_commits_for_prs.side_effect = mock_resolve

        self.mock_git.sort_commits_chronologically.return_value = ["abcdef12"]
        self.mock_git.cherry_pick.side_effect = Exception("Cherry-pick conflict")

        result = ProcessBackports(args, self.mock_git, self.mock_gh).run()

        self.assertEqual(result, 1)
        self.mock_git.checkout.assert_called_once_with(
            "release/2.0", track_remote="origin"
        )
        self.mock_git.cherry_pick.assert_called_once_with("abcdef12")
        self.mock_git.cherry_pick_abort.assert_called_once()

        self.mock_gh.update_issue_body.assert_called_once()
        call_args = self.mock_gh.update_issue_body.call_args[0]
        self.assertEqual(call_args[0], 123)
        self.assertIn("- [ ] #124 | status=error-merge-conflict", call_args[1])

        self.mock_git.commit.assert_not_called()
        self.mock_git.push.assert_not_called()


if __name__ == "__main__":
    unittest.main()
