import argparse
from unittest.mock import MagicMock, call

from tools.private.release.gh import CreatePrError
from tools.private.release.sync_changelog import SyncChangelog

pytest_plugins = ["tests.tools.private.release.release_test_helper"]


def test_sync_changelog_no_pending(mock_git, mock_gh):
    args = argparse.Namespace(
        issue=123,
        remote="origin",
        dry_run=False,
        prs=None,
        triggering_comment=None,
    )
    mock_gh.issues[123] = {
        "title": "Release 2.0.0",
        "body": """
## Checklist
- [x] Sync Changelog #124 | status=done
""",
        "labels": ["type: release"],
    }

    result = SyncChangelog(args, mock_git, mock_gh).run()

    assert result == 0
    mock_git.fetch.assert_not_called()
    mock_git.checkout.assert_not_called()


def test_sync_changelog_success(mocker, mock_git, mock_gh):
    mock_process_news_class = mocker.patch(
        "tools.private.release.sync_changelog.ProcessNews"
    )
    mock_process_news_instance = MagicMock()
    mock_process_news_instance.run.return_value = 0
    mock_process_news_class.return_value = mock_process_news_instance

    args = argparse.Namespace(
        issue=123,
        remote="origin",
        dry_run=False,
        prs=None,
        triggering_comment=None,
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
- [x] #124 | status=done rc=rc0 commit= abcdef12
""",
        "labels": ["type: release"],
    }
    mock_git.branch_exists.return_value = False
    mock_git.get_commit_sha.return_value = "main_sha"
    # Git status returns clean on initial check, dirty after process_news
    mock_git.status.side_effect = ["", "M CHANGELOG.md\nD news/124.fixed.md"]

    result = SyncChangelog(args, mock_git, mock_gh).run()

    assert result == 0
    mock_git.fetch.assert_called_once_with("origin", refspec="main")
    mock_git.checkout.assert_has_calls(
        [
            call("main", track_remote="origin"),
            call("prepare-2.0.0-backports-6affdae", create_branch=True),
            call("main"),
        ]
    )
    mock_process_news_class.assert_called_once()
    assert mock_process_news_class.call_args[0][0].version == "2.0.0"
    assert mock_process_news_class.call_args[0][0].targets == ["124"]

    mock_git.add_modified_and_deleted.assert_called_once()
    mock_git.commit.assert_called_once_with(
        "chore(release): sync changelog for v2.0.0 backports"
    )
    mock_git.push.assert_called_once_with(
        "origin",
        "prepare-2.0.0-backports-6affdae",
        set_upstream=True,
        force=True,
    )

    updated_body = mock_gh.get_issue_body(123)
    assert "- [ ] Sync Changelog #124 | status=pending pr=#1001" in updated_body


def test_sync_changelog_branch_exists(mocker, mock_git, mock_gh):
    mock_process_news_class = mocker.patch(
        "tools.private.release.sync_changelog.ProcessNews"
    )
    mock_process_news_instance = MagicMock()
    mock_process_news_instance.run.return_value = 0
    mock_process_news_class.return_value = mock_process_news_instance

    args = argparse.Namespace(
        issue=123,
        remote="origin",
        dry_run=False,
        prs=None,
        triggering_comment=None,
    )
    mock_gh.issues[123] = {
        "title": "Release 2.0.0",
        "body": """
## Checklist
- [ ] Sync Changelog #124
""",
        "labels": ["type: release"],
    }
    mock_git.branch_exists.return_value = True
    mock_git.get_commit_sha.return_value = "main_sha"
    mock_git.status.side_effect = ["", "M CHANGELOG.md"]

    result = SyncChangelog(args, mock_git, mock_gh).run()

    assert result == 0
    mock_git.checkout.assert_has_calls(
        [
            call("main", track_remote="origin"),
            call("prepare-2.0.0-backports-6affdae"),
            call("main"),
        ]
    )
    mock_git.reset_hard.assert_called_once_with(reset_to="main")


def test_sync_changelog_dry_run(mocker, mock_git, mock_gh):
    mock_process_news_class = mocker.patch(
        "tools.private.release.sync_changelog.ProcessNews"
    )
    mock_process_news_instance = MagicMock()
    mock_process_news_instance.run.return_value = 0
    mock_process_news_class.return_value = mock_process_news_instance

    args = argparse.Namespace(
        issue=123,
        remote="origin",
        dry_run=True,
        prs=None,
        triggering_comment=None,
    )
    mock_gh.issues[123] = {
        "title": "Release 2.0.0",
        "body": """
## Checklist
- [ ] Sync Changelog #124
""",
        "labels": ["type: release"],
    }
    mock_git.get_commit_sha.return_value = "main_start_sha"
    mock_git.status.side_effect = ["", "M CHANGELOG.md", "M CHANGELOG.md"]

    result = SyncChangelog(args, mock_git, mock_gh).run()

    assert result == 0
    mock_git.push.assert_not_called()
    mock_git.commit.assert_not_called()
    mock_git.reset_hard.assert_called_once_with(reset_to="main_start_sha")


def test_sync_changelog_auto_discover_issue(mocker, mock_git, mock_gh):
    mock_process_news_class = mocker.patch(
        "tools.private.release.sync_changelog.ProcessNews"
    )
    mock_process_news_instance = MagicMock()
    mock_process_news_instance.run.return_value = 0
    mock_process_news_class.return_value = mock_process_news_instance

    args = argparse.Namespace(
        issue=None,
        remote="origin",
        dry_run=False,
        prs=None,
        triggering_comment=None,
    )
    mock_gh.issues[123] = {
        "number": 123,
        "title": "Release 2.0.0",
        "body": """
## Checklist
- [ ] Sync Changelog #124
""",
        "labels": ["type: release"],
    }
    mock_git.status.side_effect = ["", "M CHANGELOG.md"]

    result = SyncChangelog(args, mock_git, mock_gh).run()

    assert result == 0
    assert (
        "- [ ] Sync Changelog #124 | status=pending pr=#1001"
        in mock_gh.get_issue_body(123)
    )


def test_sync_changelog_multiple_open_issues_fails(mock_git, mock_gh):
    args = argparse.Namespace(
        issue=None,
        remote="origin",
        dry_run=False,
        prs=None,
        triggering_comment=None,
    )
    mock_gh.issues[123] = {
        "number": 123,
        "title": "Release 2.0.0",
        "body": "",
        "labels": ["type: release"],
    }
    mock_gh.issues[124] = {
        "number": 124,
        "title": "Release 2.1.0",
        "body": "",
        "labels": ["type: release"],
    }

    result = SyncChangelog(args, mock_git, mock_gh).run()

    assert result == 1
    mock_git.fetch.assert_not_called()


def test_sync_changelog_specific_prs_arg(mocker, mock_git, mock_gh):
    mock_process_news_class = mocker.patch(
        "tools.private.release.sync_changelog.ProcessNews"
    )
    mock_process_news_instance = MagicMock()
    mock_process_news_instance.run.return_value = 0
    mock_process_news_class.return_value = mock_process_news_instance

    args = argparse.Namespace(
        issue=123,
        remote="origin",
        dry_run=False,
        prs=["#124", "125"],
        triggering_comment=None,
    )
    mock_gh.issues[123] = {
        "title": "Release 2.0.0",
        "body": """
## Checklist
- [ ] Sync Changelog #124
- [ ] Sync Changelog #125
""",
        "labels": ["type: release"],
    }
    mock_git.status.side_effect = ["", "M CHANGELOG.md"]

    result = SyncChangelog(args, mock_git, mock_gh).run()

    assert result == 0
    mock_process_news_class.assert_called_once()
    assert mock_process_news_class.call_args[0][0].targets == ["124", "125"]


def test_sync_changelog_no_changes(mocker, mock_git, mock_gh):
    mock_process_news_class = mocker.patch(
        "tools.private.release.sync_changelog.ProcessNews"
    )
    mock_process_news_instance = MagicMock()
    mock_process_news_instance.run.return_value = 0
    mock_process_news_class.return_value = mock_process_news_instance

    args = argparse.Namespace(
        issue=123,
        remote="origin",
        dry_run=False,
        prs=None,
        triggering_comment=None,
    )
    mock_gh.issues[123] = {
        "title": "Release 2.0.0",
        "body": """
## Checklist
- [ ] Sync Changelog #124
""",
        "labels": ["type: release"],
    }
    # No changes after running process news
    mock_git.status.side_effect = ["", ""]

    result = SyncChangelog(args, mock_git, mock_gh).run()

    assert result == 0
    mock_git.commit.assert_not_called()
    mock_git.push.assert_not_called()


def test_sync_changelog_process_news_failure(mocker, mock_git, mock_gh):
    mock_process_news_class = mocker.patch(
        "tools.private.release.sync_changelog.ProcessNews"
    )
    mock_process_news_instance = MagicMock()
    mock_process_news_instance.run.return_value = 1
    mock_process_news_class.return_value = mock_process_news_instance

    args = argparse.Namespace(
        issue=123,
        remote="origin",
        dry_run=False,
        prs=None,
        triggering_comment=55555,
    )
    mock_gh.issues[123] = {
        "title": "Release 2.0.0",
        "body": """
## Checklist
- [ ] Sync Changelog #124
""",
        "labels": ["type: release"],
    }
    mock_git.status.return_value = ""

    result = SyncChangelog(args, mock_git, mock_gh).run()

    assert result == 1
    assert mock_gh.reactions.get(55555) == ["-1"]


def test_sync_changelog_create_pr_failure(mocker, mock_git, mock_gh):
    mock_process_news_class = mocker.patch(
        "tools.private.release.sync_changelog.ProcessNews"
    )
    mock_process_news_instance = MagicMock()
    mock_process_news_instance.run.return_value = 0
    mock_process_news_class.return_value = mock_process_news_instance

    args = argparse.Namespace(
        issue=123,
        remote="origin",
        dry_run=False,
        prs=None,
        triggering_comment=None,
    )
    mock_gh.issues[123] = {
        "title": "Release 2.0.0",
        "body": """
## Checklist
- [ ] Sync Changelog #124
""",
        "labels": ["type: release"],
    }
    mock_git.status.side_effect = ["", "M CHANGELOG.md"]

    err = CreatePrError("Failed to create PR")
    mocker.patch.object(mock_gh, "create_pr", side_effect=err)

    result = SyncChangelog(args, mock_git, mock_gh).run()

    assert result == 1
