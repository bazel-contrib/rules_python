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
        self.mock_gh.resolve_pr_number.side_effect = lambda x: int(
            x.lstrip("#").split("/")[-1]
        )
        self.mock_git.diff.return_value = ""
        self.mock_git.apply_check.return_value = True

        # Dynamic mock for issue body
        self.issue_body = ""

        def mock_get_body(issue_num):
            return self.issue_body

        def mock_update_body(issue_num, body):
            self.issue_body = body

        self.mock_gh.get_issue_body.side_effect = mock_get_body
        self.mock_gh.update_issue_body.side_effect = mock_update_body

    def test_process_backports_no_pending(self):
        args = argparse.Namespace(
            issue=123, remote="origin", dry_run=False, add=None, triggering_comment=None
        )
        self.issue_body = "No backports here"

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
        self.issue_body = """
## Checklist
- [ ] Prepare Release
- [ ] Create Release branch
- [ ] Sync Changelog #124
- [ ] Tag Final

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
        self.mock_git.get_commit_sha.side_effect = ["12345678", "12345678", "main_sha"]
        self.mock_git.get_commit_message.return_value = 'Cherry-pick "fix bug"'
        self.mock_git.get_modified_files.return_value = ["news/124.fixed.md"]
        self.mock_git.diff.return_value = "version diff for 124"
        self.mock_git.apply_check.return_value = True
        self.mock_gh.create_pr.return_value = "https://github.com/foo/bar/pull/999"

        result = ProcessBackports(args, self.mock_git, self.mock_gh).run()

        self.assertEqual(result, 0)
        self.mock_git.fetch.assert_has_calls(
            [
                call("origin", tags=True, force=True),
                call("origin"),
                call("origin", refspec="main"),
            ]
        )
        self.mock_git.checkout.assert_has_calls(
            [
                call("release/2.0", track_remote="origin"),
                call("main", track_remote="origin"),
                call("prepare-2.0.0-backports-6affdae", create_branch=True),
                call("release/2.0"),
            ]
        )
        self.mock_git.cherry_pick.assert_called_once_with("abcdef12")
        self.mock_git.diff.assert_called_once()
        self.mock_git.apply_check.assert_called_once_with(unittest.mock.ANY)
        self.mock_git.apply.assert_called_once_with(unittest.mock.ANY)
        self.mock_changelog_news.update_changelog.assert_has_calls(
            [
                call("2.0.0", "2026-07-01"),
                call(
                    "2.0.0",
                    "2026-07-01",
                    news_files=["news/124.fixed.md"],
                    delete_news=True,
                ),
            ]
        )
        self.assertEqual(self.mock_git.add_modified_and_deleted.call_count, 2)
        self.mock_replace_version_next.assert_called_once_with("2.0.0")
        self.mock_git.commit.assert_has_calls(
            [
                call('Cherry-pick "fix bug"\n\nWork towards #123', amend=True),
                call("chore(release): sync changelog for v2.0.0 backports"),
            ]
        )
        self.mock_git.push.assert_has_calls(
            [
                call("origin", "release/2.0"),
                call(
                    "origin",
                    "prepare-2.0.0-backports-6affdae",
                    set_upstream=True,
                    force=True,
                ),
            ]
        )

        self.mock_gh.create_pr.assert_called_once_with(
            title="chore(release): sync changelog for v2.0.0 backports",
            body="Updates CHANGELOG.md and removes news files for backports:\n- #124\n\nWork towards #123\nRelease-Tracking-Issue: #123",
            base="main",
            labels=["type: sync-changelog"],
        )
        self.mock_gh.enable_auto_merge.assert_called_once_with(999)

        self.assertEqual(self.mock_gh.update_issue_body.call_count, 2)
        call_args_list = self.mock_gh.update_issue_body.call_args_list
        self.assertEqual(call_args_list[0][0][0], 123)
        self.assertIn(
            "- [x] #124 | status=done rc=rc0 commit= 12345678", call_args_list[0][0][1]
        )
        self.assertEqual(call_args_list[1][0][0], 123)
        self.assertIn(
            "- [ ] Sync Changelog #124 | status=pending pr=#999",
            call_args_list[1][0][1],
        )

    @patch("tools.private.release.process_backports.datetime")
    def test_process_backports_sync_branch_exists(self, mock_datetime):
        mock_datetime.date.today.return_value = datetime.date(2026, 7, 1)
        args = argparse.Namespace(
            issue=123, remote="origin", dry_run=False, add=None, triggering_comment=None
        )
        self.mock_gh.get_issue_title.return_value = "Release 2.0.0"
        self.issue_body = """
## Checklist
- [ ] Prepare Release
- [ ] Create Release branch
- [ ] Sync Changelog #124
- [ ] Tag Final

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
        self.mock_git.get_commit_sha.side_effect = ["12345678", "12345678", "main_sha"]
        self.mock_git.get_commit_message.return_value = 'Cherry-pick "fix bug"'
        self.mock_git.get_modified_files.return_value = ["news/124.fixed.md"]
        self.mock_git.diff.return_value = "version diff for 124"
        self.mock_git.apply_check.return_value = True
        self.mock_gh.create_pr.return_value = "https://github.com/foo/bar/pull/999"

        # Configure branch to exist
        self.mock_git.branch_exists.return_value = True

        result = ProcessBackports(args, self.mock_git, self.mock_gh).run()

        self.assertEqual(result, 0)
        self.mock_git.fetch.assert_has_calls(
            [
                call("origin", tags=True, force=True),
                call("origin"),
                call("origin", refspec="main"),
            ]
        )
        self.mock_git.checkout.assert_has_calls(
            [
                call("release/2.0", track_remote="origin"),
                call("main", track_remote="origin"),
                # Called without create_branch=True
                call("prepare-2.0.0-backports-6affdae"),
                call("release/2.0"),
            ]
        )
        # Verify reset_hard was called to reset the existing branch to main
        self.mock_git.reset_hard.assert_has_calls(
            [
                call(reset_to="main"),
            ]
        )
        self.mock_git.cherry_pick.assert_called_once_with("abcdef12")
        self.mock_git.diff.assert_called_once()
        self.mock_git.apply_check.assert_called_once_with(unittest.mock.ANY)
        self.mock_git.apply.assert_called_once_with(unittest.mock.ANY)
        self.mock_changelog_news.update_changelog.assert_has_calls(
            [
                call("2.0.0", "2026-07-01"),
                call(
                    "2.0.0",
                    "2026-07-01",
                    news_files=["news/124.fixed.md"],
                    delete_news=True,
                ),
            ]
        )
        self.assertEqual(self.mock_git.add_modified_and_deleted.call_count, 2)
        self.mock_replace_version_next.assert_called_once_with("2.0.0")
        self.mock_git.commit.assert_has_calls(
            [
                call('Cherry-pick "fix bug"\n\nWork towards #123', amend=True),
                call("chore(release): sync changelog for v2.0.0 backports"),
            ]
        )
        self.mock_git.push.assert_has_calls(
            [
                call("origin", "release/2.0"),
                call(
                    "origin",
                    "prepare-2.0.0-backports-6affdae",
                    set_upstream=True,
                    force=True,
                ),
            ]
        )

        self.mock_gh.create_pr.assert_called_once_with(
            title="chore(release): sync changelog for v2.0.0 backports",
            body="Updates CHANGELOG.md and removes news files for backports:\n- #124\n\nWork towards #123\nRelease-Tracking-Issue: #123",
            base="main",
            labels=["type: sync-changelog"],
        )
        self.mock_gh.enable_auto_merge.assert_called_once_with(999)

        self.assertEqual(self.mock_gh.update_issue_body.call_count, 2)
        call_args_list = self.mock_gh.update_issue_body.call_args_list
        self.assertEqual(call_args_list[0][0][0], 123)
        self.assertIn(
            "- [x] #124 | status=done rc=rc0 commit= 12345678", call_args_list[0][0][1]
        )
        self.assertEqual(call_args_list[1][0][0], 123)
        self.assertIn(
            "- [ ] Sync Changelog #124 | status=pending pr=#999",
            call_args_list[1][0][1],
        )

    @patch("tools.private.release.process_backports.datetime")
    def test_process_backports_dry_run(self, mock_datetime):
        mock_datetime.date.today.return_value = datetime.date(2026, 7, 1)
        args = argparse.Namespace(
            issue=123, remote="origin", dry_run=True, add=None, triggering_comment=None
        )
        self.mock_gh.get_issue_title.return_value = "Release 2.0.0"
        self.issue_body = """
## Checklist
- [ ] Prepare Release
- [ ] Create Release branch
- [ ] Sync Changelog #124
- [ ] Tag Final

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
        self.mock_git.get_commit_sha.side_effect = ["12345678", "main_sha"]
        self.mock_git.get_commit_message.return_value = 'Cherry-pick "fix bug"'
        self.mock_git.get_modified_files.return_value = ["news/124.fixed.md"]
        self.mock_git.diff.return_value = "version diff for 124"
        self.mock_git.apply_check.return_value = True

        result = ProcessBackports(args, self.mock_git, self.mock_gh).run()

        self.assertEqual(result, 0)
        self.mock_git.fetch.assert_has_calls(
            [
                call("origin", tags=True, force=True),
                call("origin"),
                call("origin", refspec="main"),
            ]
        )
        self.mock_git.checkout.assert_has_calls(
            [
                call("release/2.0", track_remote="origin"),
                call("main", track_remote="origin"),
                call("release/2.0"),
            ]
        )
        self.mock_git.cherry_pick.assert_called_once_with("abcdef12")
        self.mock_git.diff.assert_called_once()
        self.mock_git.apply_check.assert_called_once_with(unittest.mock.ANY)
        self.mock_git.apply.assert_not_called()
        self.mock_changelog_news.update_changelog.assert_has_calls(
            [
                call("2.0.0", "2026-07-01"),
                call(
                    "2.0.0",
                    "2026-07-01",
                    news_files=["news/124.fixed.md"],
                    delete_news=True,
                ),
            ]
        )
        self.assertEqual(self.mock_git.add_modified_and_deleted.call_count, 1)
        self.mock_replace_version_next.assert_called_once_with("2.0.0")
        self.mock_git.commit.assert_called_once_with(
            'Cherry-pick "fix bug"\n\nWork towards #123', amend=True
        )
        self.mock_git.reset_hard.assert_has_calls(
            [
                call(reset_to="12345678"),
                call(reset_to="main_sha"),
            ]
        )
        self.mock_git.push.assert_not_called()
        self.mock_gh.update_issue_body.assert_not_called()

    def test_process_backports_ignored_and_failed_states(self):
        args = argparse.Namespace(
            issue=123, remote="origin", dry_run=False, add=None, triggering_comment=None
        )
        self.mock_gh.get_issue_title.return_value = "Release 2.0.0"
        self.issue_body = """
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
        self.issue_body = """
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
        self.issue_body = """
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

    @patch("tools.private.release.process_backports.datetime")
    def test_process_backports_add_backports_and_auto_add_rc_task(self, mock_datetime):
        mock_datetime.date.today.return_value = datetime.date(2026, 7, 1)
        args = argparse.Namespace(
            issue=123,
            remote="origin",
            dry_run=False,
            add=["https://github.com/bazel-contrib/rules_python/pull/124"],
            triggering_comment=None,
        )
        self.mock_gh.get_issue_title.return_value = "Release 2.0.0"
        self.issue_body = """
## Checklist
- [x] Prepare Release | status=done pr=#122 commit=abcdef12
- [x] Create Release branch | status=done branch=release/2.0 commit=abcdef12
- [x] Tag RC0 | status=done tag=2.0.0-rc0 commit=abcdef12
- [ ] Tag Final

## Backports
"""
        self.mock_git.get_remote_tags.return_value = ["2.0.0-rc0"]
        self.mock_git.get_commit_sha.return_value = "12345678"
        self.mock_git.get_commit_message.return_value = 'Cherry-pick "fix bug"'

        def mock_resolve(items):
            for item in items:
                if item.pr_ref == "#124":
                    item.commit = "abcdef12"
                    item.status = "done"
            return items

        self.mock_gh.get_merge_commits_for_prs.side_effect = mock_resolve
        self.mock_git.sort_commits_chronologically.return_value = ["abcdef12"]

        # Mock create_pr to return a string to avoid int(MagicMock) returning 1
        self.mock_gh.create_pr.return_value = "https://github.com/foo/bar/pull/999"

        result = ProcessBackports(args, self.mock_git, self.mock_gh).run()

        self.assertEqual(result, 0)

        # update_issue_body should be called 3 times:
        # 1. When adding backports and auto-adding Tag RC1 task.
        # 2. When updating the backport status to done.
        # 3. When updating the sync task status to pending.
        self.assertEqual(self.mock_gh.update_issue_body.call_count, 3)

        call1_args = self.mock_gh.update_issue_body.call_args_list[0][0]
        call2_args = self.mock_gh.update_issue_body.call_args_list[1][0]

        self.assertEqual(call1_args[0], 123)
        self.assertIn("- [ ] #124", call1_args[1])
        self.assertIn("- [ ] Tag RC1", call1_args[1])
        self.assertIn("- [ ] Sync Changelog #124", call1_args[1])
        self.assertIn(
            "- [x] Tag RC0 | status=done tag=2.0.0-rc0 commit=abcdef12\n- [ ]"
            " Tag RC1\n- [ ] Sync Changelog #124\n- [ ] Tag Final",
            call1_args[1].strip(),
        )

        self.assertEqual(call2_args[0], 123)
        self.assertIn("- [x] #124 | status=done rc=rc1 commit= 12345678", call2_args[1])

        call3_args = self.mock_gh.update_issue_body.call_args_list[2][0]
        self.assertEqual(call3_args[0], 123)
        self.assertIn(
            "- [ ] Sync Changelog #124 | status=pending pr=#999", call3_args[1]
        )

    @patch("tools.private.release.process_backports.datetime")
    def test_process_backports_add_backports_marks_invalid(self, mock_datetime):
        mock_datetime.date.today.return_value = datetime.date(2026, 7, 1)
        args = argparse.Namespace(
            issue=123,
            remote="origin",
            dry_run=False,
            add=["124", "invalid", "125"],
            triggering_comment=None,
        )
        self.mock_gh.get_issue_title.return_value = "Release 2.0.0"
        self.issue_body = """
## Checklist
- [x] Prepare Release | status=done pr=#122 commit=abcdef12
- [x] Create Release branch | status=done branch=release/2.0 commit=abcdef12
- [x] Tag RC0 | status=done tag=2.0.0-rc0 commit=abcdef12
- [ ] Tag Final

## Backports
"""
        self.mock_git.get_remote_tags.return_value = ["2.0.0-rc0"]
        self.mock_git.get_commit_sha.return_value = "1234567890"
        self.mock_git.get_commit_message.return_value = 'Cherry-pick "fix bug"'

        def mock_resolve(items):
            # Both 124 and 125 should be processed, 'invalid' should be ignored (it has error status)
            for item in items:
                if item.pr_ref == "#124":
                    item.commit = "sha_124"
                    item.status = "done"
                elif item.pr_ref == "#125":
                    item.commit = "sha_125"
                    item.status = "done"
            return items

        self.mock_gh.get_merge_commits_for_prs.side_effect = mock_resolve
        self.mock_git.sort_commits_chronologically.return_value = ["sha_124", "sha_125"]
        self.mock_gh.create_pr.return_value = "https://github.com/foo/bar/pull/999"

        result = ProcessBackports(args, self.mock_git, self.mock_gh).run()

        self.assertEqual(result, 0)
        # Should have updated body to add 124, 125, and invalid
        # update_issue_body should be called 4 times:
        # 1. When adding backports.
        # 2. When updating 124 status to done.
        # 3. When updating 125 status to done.
        # 4. When updating sync tasks status to pending.
        self.assertEqual(self.mock_gh.update_issue_body.call_count, 4)
        call1_args = self.mock_gh.update_issue_body.call_args_list[0][0]
        self.assertIn("- [ ] #124", call1_args[1])
        self.assertIn("- [ ] #125", call1_args[1])
        self.assertIn("- [ ] invalid | status=error-invalid-pr", call1_args[1])
        self.assertIn("- [ ] Sync Changelog #124", call1_args[1])
        self.assertIn("- [ ] Sync Changelog #125", call1_args[1])

        call4_args = self.mock_gh.update_issue_body.call_args_list[3][0]
        self.assertIn(
            "- [ ] Sync Changelog #124 | status=pending pr=#999", call4_args[1]
        )
        self.assertIn(
            "- [ ] Sync Changelog #125 | status=pending pr=#999", call4_args[1]
        )

    @patch("tools.private.release.process_backports.datetime")
    def test_process_backports_version_sync_failure(self, mock_datetime):
        mock_datetime.date.today.return_value = datetime.date(2026, 7, 1)
        args = argparse.Namespace(
            issue=123, remote="origin", dry_run=False, add=None, triggering_comment=None
        )
        self.mock_gh.get_issue_title.return_value = "Release 2.0.0"
        self.issue_body = """
## Checklist
- [ ] Prepare Release
- [ ] Create Release branch
- [ ] Sync Changelog #124
- [ ] Sync Changelog #125
- [ ] Tag Final

## Backports
- [ ] #124 | status=pending
- [ ] #125 | status=pending
"""
        self.mock_git.get_remote_tags.return_value = []

        def mock_resolve(items):
            for item in items:
                if item.pr_ref in ("#124", "#125"):
                    item.commit = "sha_" + item.pr_ref.lstrip("#")
                    item.status = "done"
            return items

        self.mock_gh.get_merge_commits_for_prs.side_effect = mock_resolve

        self.mock_git.sort_commits_chronologically.return_value = ["sha_124", "sha_125"]
        self.mock_git.get_commit_sha.side_effect = [
            "12345678",
            "sha_124_amended",
            "sha_125_amended",
            "main_sha",
        ]
        self.mock_git.get_commit_message.return_value = 'Cherry-pick "fix bug"'
        self.mock_git.get_modified_files.side_effect = [
            ["news/124.fixed.md"],
            ["news/125.fixed.md"],
        ]
        self.mock_git.diff.side_effect = ["diff 124", "diff 125"]
        self.mock_git.apply_check.side_effect = [False, True]
        self.mock_gh.create_pr.return_value = "https://github.com/foo/bar/pull/999"

        result = ProcessBackports(args, self.mock_git, self.mock_gh).run()

        self.assertEqual(result, 0)
        self.mock_git.fetch.assert_has_calls(
            [
                call("origin", tags=True, force=True),
                call("origin"),
                call("origin", refspec="main"),
            ]
        )
        self.mock_git.checkout.assert_has_calls(
            [
                call("release/2.0", track_remote="origin"),
                call("main", track_remote="origin"),
                call("prepare-2.0.0-backports-b552a96", create_branch=True),
                call("release/2.0"),
            ]
        )
        self.mock_git.cherry_pick.assert_has_calls(
            [
                call("sha_124"),
                call("sha_125"),
            ]
        )
        # diff should be called for each successful cherry-pick
        self.assertEqual(self.mock_git.diff.call_count, 2)
        # apply_check should be called for both patches
        self.assertEqual(self.mock_git.apply_check.call_count, 2)
        # apply should only be called for 125 (since 124 failed check)
        self.mock_git.apply.assert_called_once_with(unittest.mock.ANY)

        self.mock_changelog_news.update_changelog.assert_has_calls(
            [
                call("2.0.0", "2026-07-01"),
                call("2.0.0", "2026-07-01"),
                call(
                    "2.0.0",
                    "2026-07-01",
                    news_files=["news/124.fixed.md", "news/125.fixed.md"],
                    delete_news=True,
                ),
            ]
        )
        # add_modified_and_deleted called:
        # - once per cherry-pick (2)
        # - once on main backport branch (1)
        # Total = 3
        self.assertEqual(self.mock_git.add_modified_and_deleted.call_count, 3)
        # replace_version_next called once per cherry-pick
        self.assertEqual(self.mock_replace_version_next.call_count, 2)

        self.mock_git.commit.assert_has_calls(
            [
                call('Cherry-pick "fix bug"\n\nWork towards #123', amend=True),
                call('Cherry-pick "fix bug"\n\nWork towards #123', amend=True),
                call("chore(release): sync changelog for v2.0.0 backports"),
            ]
        )
        self.mock_git.push.assert_has_calls(
            [
                call("origin", "release/2.0"),
                call("origin", "release/2.0"),
                call(
                    "origin",
                    "prepare-2.0.0-backports-b552a96",
                    set_upstream=True,
                    force=True,
                ),
            ]
        )

        # PR body should contain warning about 124
        expected_body = (
            "Updates CHANGELOG.md and removes news files for backports:\n"
            "- #124\n"
            "- #125\n"
            "\n"
            "Warning: These PRs failed to update their version markers:\n"
            "- #124\n"
            "\n"
            "Work towards #123\n"
            "Release-Tracking-Issue: #123"
        )
        self.mock_gh.create_pr.assert_called_once_with(
            title="chore(release): sync changelog for v2.0.0 backports",
            body=expected_body,
            base="main",
            labels=["type: sync-changelog"],
        )
        self.mock_gh.enable_auto_merge.assert_called_once_with(999)

        # update_issue_body called 3 times (twice for backports, once for sync tasks)
        self.assertEqual(self.mock_gh.update_issue_body.call_count, 3)
        call3_args = self.mock_gh.update_issue_body.call_args_list[2][0]
        self.assertIn(
            "- [ ] Sync Changelog #124 | status=pending pr=#999", call3_args[1]
        )
        self.assertIn(
            "- [ ] Sync Changelog #125 | status=pending pr=#999", call3_args[1]
        )


if __name__ == "__main__":
    unittest.main()
