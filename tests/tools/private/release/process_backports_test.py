import argparse
import datetime
import logging
from unittest.mock import call

from tools.private.release.process_backports import ProcessBackports

pytest_plugins = ["tests.tools.private.release.release_test_helper"]


def test_process_backports_no_pending(mock_git, mock_gh):
    args = argparse.Namespace(
        issue=123, remote="origin", dry_run=False, add=None, triggering_comment=None
    )
    mock_gh.issues[123] = {
        "title": "Release 2.0.0",
        "body": "No backports here",
        "labels": ["type: release"],
    }

    result = ProcessBackports(args, mock_git, mock_gh).run()

    assert result == 0
    mock_git.fetch.assert_not_called()


def test_process_backports_success(mocker, mock_git, mock_gh):
    mock_changelog = mocker.patch(
        "tools.private.release.process_backports.changelog_news"
    )
    mock_replace = mocker.patch(
        "tools.private.release.process_backports.replace_version_next"
    )
    mock_datetime = mocker.patch("tools.private.release.process_backports.datetime")
    mock_datetime.date.today.return_value = datetime.date(2026, 7, 1)

    args = argparse.Namespace(
        issue=123, remote="origin", dry_run=False, add=None, triggering_comment=None
    )
    mock_gh.issues[123] = {
        "title": "Release 2.0.0",
        "body": """
## Checklist
- [ ] Prepare Release
- [ ] Create Release branch
- [ ] Sync Changelog #124
- [ ] Tag Final

## Backports
- [ ] #124 | status=pending
""",
        "labels": ["type: release"],
    }
    mock_gh.prs[124] = {
        "state": "MERGED",
        "mergeCommit": {"oid": "abcdef12"},
    }
    mock_git.get_remote_tags.return_value = []
    mock_git.sort_commits_chronologically.return_value = ["abcdef12"]
    mock_git.get_commit_sha.side_effect = ["12345678", "12345678"]
    mock_git.get_commit_message.return_value = 'Cherry-pick "fix bug"'

    result = ProcessBackports(args, mock_git, mock_gh).run()

    assert result == 0
    mock_git.fetch.assert_has_calls(
        [
            call("origin", tags=True, force=True),
            call("origin"),
        ]
    )
    mock_git.checkout.assert_called_once_with("release/2.0", track_remote="origin")
    mock_git.cherry_pick.assert_called_once_with("abcdef12")
    mock_changelog.update_changelog.assert_called_once_with("2.0.0", "2026-07-01")
    mock_git.add_modified_and_deleted.assert_called_once()
    mock_replace.assert_called_once_with("2.0.0")
    mock_git.commit.assert_called_once_with(
        'Cherry-pick "fix bug"\n\nWork towards #123', amend=True
    )
    mock_git.push.assert_called_once_with("origin", "release/2.0")

    updated_body = mock_gh.get_issue_body(123)
    assert "- [x] #124 | status=done rc=rc0 commit= 12345678" in updated_body
    # Sync Changelog task remains untouched by process_backports
    assert "- [ ] Sync Changelog #124" in updated_body


def test_process_backports_dry_run(mocker, mock_git, mock_gh):
    mocker.patch("tools.private.release.process_backports.changelog_news")
    mocker.patch("tools.private.release.process_backports.replace_version_next")
    mock_datetime = mocker.patch("tools.private.release.process_backports.datetime")
    mock_datetime.date.today.return_value = datetime.date(2026, 7, 1)

    args = argparse.Namespace(
        issue=123, remote="origin", dry_run=True, add=None, triggering_comment=None
    )
    mock_gh.issues[123] = {
        "title": "Release 2.0.0",
        "body": """
## Checklist
- [ ] Prepare Release
- [ ] Create Release branch
- [ ] Sync Changelog #124
- [ ] Tag Final

## Backports
- [ ] #124 | status=pending
""",
        "labels": ["type: release"],
    }
    mock_gh.prs[124] = {
        "state": "MERGED",
        "mergeCommit": {"oid": "abcdef12"},
    }
    mock_git.get_remote_tags.return_value = []
    mock_git.sort_commits_chronologically.return_value = ["abcdef12"]
    mock_git.get_commit_sha.return_value = "12345678"
    mock_git.get_commit_message.return_value = 'Cherry-pick "fix bug"'

    result = ProcessBackports(args, mock_git, mock_gh).run()

    assert result == 0
    mock_git.push.assert_not_called()


def test_process_backports_ignored_and_failed_states(mock_git, mock_gh):
    args = argparse.Namespace(
        issue=123, remote="origin", dry_run=False, add=None, triggering_comment=None
    )
    mock_gh.issues[123] = {
        "title": "Release 2.0.0",
        "body": """
## Checklist
- [ ] Prepare Release
- [ ] Create Release branch

## Backports
- [ ] #124 | status=pending
- [ ] #125 | status=pending
- [ ] #126 | status=pending
""",
        "labels": ["type: release"],
    }
    mock_git.get_remote_tags.return_value = []

    mock_gh.prs[124] = {"state": "OPEN"}
    mock_gh.prs[125] = {"state": "OPEN", "isDraft": True}
    mock_gh.prs[126] = {"state": "CLOSED"}

    result = ProcessBackports(args, mock_git, mock_gh).run()

    assert result == 1
    updated_body = mock_gh.get_issue_body(123)
    assert "- [ ] #126 | status=error-closed-pr" in updated_body
    mock_git.checkout.assert_not_called()
    mock_git.cherry_pick.assert_not_called()


def test_process_backports_ignored_error_status(mock_git, mock_gh):
    args = argparse.Namespace(
        issue=123, remote="origin", dry_run=False, add=None, triggering_comment=None
    )
    mock_gh.issues[123] = {
        "title": "Release 2.0.0",
        "body": """
## Checklist
- [ ] Prepare Release
- [ ] Create Release branch

## Backports
- [ ] #124 | status=error-merge-conflict
- [ ] #125 | status=error-some-other-error
""",
        "labels": ["type: release"],
    }
    mock_git.get_remote_tags.return_value = []

    result = ProcessBackports(args, mock_git, mock_gh).run()

    assert result == 0
    mock_git.checkout.assert_not_called()


def test_process_backports_cherry_pick_failed(mocker, mock_git, mock_gh):
    mock_datetime = mocker.patch("tools.private.release.process_backports.datetime")
    mock_datetime.date.today.return_value = datetime.date(2026, 7, 1)
    args = argparse.Namespace(
        issue=123, remote="origin", dry_run=False, add=None, triggering_comment=None
    )
    mock_gh.issues[123] = {
        "title": "Release 2.0.0",
        "body": """
## Checklist
- [ ] Prepare Release
- [ ] Create Release branch

## Backports
- [ ] #124 | status=pending
""",
        "labels": ["type: release"],
    }
    mock_gh.prs[124] = {
        "state": "MERGED",
        "mergeCommit": {"oid": "abcdef12"},
    }
    mock_git.get_remote_tags.return_value = []
    mock_git.sort_commits_chronologically.return_value = ["abcdef12"]
    mock_git.cherry_pick.side_effect = Exception("Cherry-pick conflict")

    result = ProcessBackports(args, mock_git, mock_gh).run()

    assert result == 1
    mock_git.checkout.assert_called_once_with("release/2.0", track_remote="origin")
    mock_git.cherry_pick.assert_called_once_with("abcdef12")
    mock_git.cherry_pick_abort.assert_called_once()

    updated_body = mock_gh.get_issue_body(123)
    assert "- [ ] #124 | status=error-merge-conflict" in updated_body
    mock_git.commit.assert_not_called()
    mock_git.push.assert_not_called()


def test_process_backports_add_backports_and_auto_add_rc_task(
    mocker, mock_git, mock_gh
):
    mocker.patch("tools.private.release.process_backports.changelog_news")
    mocker.patch("tools.private.release.process_backports.replace_version_next")
    mock_datetime = mocker.patch("tools.private.release.process_backports.datetime")
    mock_datetime.date.today.return_value = datetime.date(2026, 7, 1)
    args = argparse.Namespace(
        issue=123,
        remote="origin",
        dry_run=False,
        add=["https://github.com/bazel-contrib/rules_python/pull/124"],
        triggering_comment=None,
    )
    mock_gh.issues[123] = {
        "title": "Release 2.0.0",
        "body": """
## Checklist
- [x] Prepare Release | status=done pr=#122 commit=abcdef12
- [x] Create Release branch | status=done branch=release/2.0 commit=abcdef12
- [x] Tag RC0 | status=done tag=2.0.0-rc0 commit=abcdef12
- [ ] Tag Final

## Backports
""",
        "labels": ["type: release"],
    }
    mock_gh.prs[124] = {
        "state": "MERGED",
        "mergeCommit": {"oid": "abcdef12"},
    }
    mock_git.get_remote_tags.return_value = ["2.0.0-rc0"]
    mock_git.get_commit_sha.return_value = "12345678"
    mock_git.get_commit_message.return_value = 'Cherry-pick "fix bug"'
    mock_git.sort_commits_chronologically.return_value = ["abcdef12"]

    result = ProcessBackports(args, mock_git, mock_gh).run()

    assert result == 0
    updated_body = mock_gh.get_issue_body(123)
    assert "- [x] #124 | status=done rc=rc1 commit= 12345678" in updated_body
    assert "- [ ] Sync Changelog #124" in updated_body


def test_process_backports_add_backports_marks_invalid(mocker, mock_git, mock_gh):
    mocker.patch("tools.private.release.process_backports.changelog_news")
    mocker.patch("tools.private.release.process_backports.replace_version_next")
    mock_datetime = mocker.patch("tools.private.release.process_backports.datetime")
    mock_datetime.date.today.return_value = datetime.date(2026, 7, 1)
    args = argparse.Namespace(
        issue=123,
        remote="origin",
        dry_run=False,
        add=["124", "invalid", "125"],
        triggering_comment=None,
    )
    mock_gh.issues[123] = {
        "title": "Release 2.0.0",
        "body": """
## Checklist
- [x] Prepare Release | status=done pr=#122 commit=abcdef12
- [x] Create Release branch | status=done branch=release/2.0 commit=abcdef12
- [x] Tag RC0 | status=done tag=2.0.0-rc0 commit=abcdef12
- [ ] Tag Final

## Backports
""",
        "labels": ["type: release"],
    }
    mock_gh.prs[124] = {
        "state": "MERGED",
        "mergeCommit": {"oid": "sha_124"},
    }
    mock_gh.prs[125] = {
        "state": "MERGED",
        "mergeCommit": {"oid": "sha_125"},
    }
    mock_git.get_remote_tags.return_value = ["2.0.0-rc0"]
    mock_git.get_commit_sha.return_value = "1234567890"
    mock_git.get_commit_message.return_value = 'Cherry-pick "fix bug"'
    mock_git.sort_commits_chronologically.return_value = ["sha_124", "sha_125"]

    result = ProcessBackports(args, mock_git, mock_gh).run()

    assert result == 0
    updated_body = mock_gh.get_issue_body(123)
    assert "- [ ] invalid | status=error-invalid-pr" in updated_body
    assert "- [ ] Sync Changelog #124" in updated_body
    assert "- [ ] Sync Changelog #125" in updated_body


def test_process_backports_logs_no_pending(mock_git, mock_gh, caplog):
    args = argparse.Namespace(
        issue=123,
        remote="origin",
        dry_run=False,
        add=None,
        triggering_comment=None,
    )
    mock_gh.issues[123] = {
        "title": "Release 2.0.0",
        "body": "No backports here",
        "labels": ["type: release"],
    }

    with caplog.at_level(logging.INFO):
        result = ProcessBackports(args, mock_git, mock_gh).run()

    assert result == 0
    assert "No pending backports found." in caplog.text
