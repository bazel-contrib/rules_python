import argparse
from unittest.mock import ANY, call

from tools.private.release.backport_prepare import BackportPrepare
from tools.private.release.gh import BACKPORT_LABEL

pytest_plugins = ["tests.tools.private.release.release_test_helper"]


def test_prepare_from_issue_success(mocker, mock_git, mock_gh):
    # Arrange
    args = argparse.Namespace(
        issue=123,
        pr=None,
        from_minor=None,
        to_minor=None,
        remote="my-remote",
        dry_run=False,
    )

    # Setup backport issue in mock GH
    backport_body = "* PR: #456\n* From version: 1.7\n* To version: 1.9\n"
    mock_gh.issues[123] = {
        "title": "Backport: #456",
        "body": backport_body,
        "labels": ["type: backport-pr"],
        "number": 123,
        "url": "https://github.com/.../issues/123",
    }

    # Setup PR info in mock GH
    mock_gh.prs[456] = {
        "state": "MERGED",
        "mergeCommit": {"oid": "pr_merge_sha_12345"},
    }

    # Mock remote branches
    mock_git.get_remote_branches.return_value = [
        "main",
        "release/1.6",
        "release/1.7",
        "release/1.8",
        "release/1.9",
        "release/2.0",
    ]
    mock_git.get_current_branch.return_value = "work-branch"

    mock_news = mocker.patch("tools.private.release.backport_prepare.changelog_news")
    mock_det = mocker.patch(
        "tools.private.release.backport_prepare.determine_next_version"
    )
    mock_det.side_effect = ["1.7.2", "1.8.1", "1.9.0"]

    # Act
    result = BackportPrepare(args, mock_git, mock_gh).run()

    # Assert
    assert result == 0
    mock_git.fetch.assert_called_once_with("my-remote", tags=True, force=True)

    # Verify checkouts and cherry-picks
    mock_git.checkout.assert_has_calls(
        [
            call("release/1.7", track_remote="my-remote"),
            call("release/1.8", track_remote="my-remote"),
            call("release/1.9", track_remote="my-remote"),
            call("work-branch"),  # Restored branch
        ]
    )

    mock_git.cherry_pick.assert_has_calls(
        [
            call("pr_merge_sha_12345"),
            call("pr_merge_sha_12345"),
            call("pr_merge_sha_12345"),
        ]
    )

    # Verify changelog updates
    mock_news.update_changelog.assert_has_calls(
        [
            call("1.7.2", ANY),
            call("1.8.1", ANY),
            call("1.9.0", ANY),
        ]
    )

    # Verify issue body update
    expected_body = (
        "* PR: #456\n"
        "* From version: 1.7\n"
        "* To version: 1.9\n"
        "\n"
        "## Tasks\n"
        "\n"
        "- [x] Verify apply 1.7 | status=success\n"
        "- [x] Verify apply 1.8 | status=success\n"
        "- [x] Verify apply 1.9 | status=success\n"
        "- [ ] Track Release 1.7.2\n"
        "- [ ] Track Release 1.8.1\n"
        "- [ ] Track Release 1.9.0"
    )
    assert mock_gh.issues[123]["body"] == expected_body


def test_prepare_manual_success(mocker, mock_git, mock_gh):
    # Arrange
    args = argparse.Namespace(
        issue=None,
        pr="#456",
        from_minor="1.7",
        to_minor="1.8",
        remote="my-remote",
        dry_run=False,
    )
    mock_gh.prs[456] = {
        "state": "MERGED",
        "mergeCommit": {"oid": "pr_merge_sha_12345"},
    }
    mock_git.get_remote_branches.return_value = [
        "release/1.7",
        "release/1.8",
    ]
    mock_git.get_current_branch.return_value = "work-branch"

    mocker.patch("tools.private.release.backport_prepare.changelog_news")
    mock_det = mocker.patch(
        "tools.private.release.backport_prepare.determine_next_version"
    )
    mock_det.side_effect = ["1.7.2", "1.8.1"]

    # Act
    result = BackportPrepare(args, mock_git, mock_gh).run()

    # Assert
    assert result == 0
    assert 1001 in mock_gh.issues
    issue = mock_gh.issues[1001]
    assert issue["title"] == "Backport: #456"
    assert issue["labels"] == [BACKPORT_LABEL]
    body = issue["body"]
    assert "- [x] Verify apply 1.7 | status=success" in body
    assert "- [x] Verify apply 1.8 | status=success" in body
    assert "- [ ] Track Release 1.7.2" in body
    assert "- [ ] Track Release 1.8.1" in body


def test_prepare_manual_with_patch_versions(mocker, mock_git, mock_gh):
    # Arrange
    args = argparse.Namespace(
        issue=None,
        pr="#456",
        from_minor="1.7.0",
        to_minor="1.8.0",
        remote="my-remote",
        dry_run=False,
    )
    mock_gh.prs[456] = {
        "state": "MERGED",
        "mergeCommit": {"oid": "pr_merge_sha_12345"},
    }
    mock_git.get_remote_branches.return_value = [
        "release/1.7",
        "release/1.8",
    ]
    mock_git.get_current_branch.return_value = "work-branch"

    mocker.patch("tools.private.release.backport_prepare.changelog_news")
    mock_det = mocker.patch(
        "tools.private.release.backport_prepare.determine_next_version"
    )
    mock_det.side_effect = ["1.7.2", "1.8.1"]

    # Act
    result = BackportPrepare(args, mock_git, mock_gh).run()

    # Assert
    assert result == 0
    assert 1001 in mock_gh.issues
    body = mock_gh.issues[1001]["body"]
    assert "- [x] Verify apply 1.7 | status=success" in body
    assert "- [x] Verify apply 1.8 | status=success" in body


def test_prepare_verify_failed(mocker, mock_git, mock_gh):
    # Arrange
    args = argparse.Namespace(
        issue=123,
        pr=None,
        from_minor=None,
        to_minor=None,
        remote="my-remote",
        dry_run=False,
    )
    issue_body = "* PR: #456\n* From version: 1.7\n* To version: 1.8\n"
    mock_gh.issues[123] = {
        "title": "Backport: #456",
        "body": issue_body,
        "labels": ["type: backport-pr"],
        "number": 123,
        "url": "https://github.com/.../issues/123",
    }
    mock_gh.prs[456] = {
        "state": "MERGED",
        "mergeCommit": {"oid": "pr_merge_sha_12345"},
    }
    mock_git.get_remote_branches.return_value = [
        "release/1.7",
        "release/1.8",
    ]
    mock_git.get_current_branch.return_value = "work-branch"

    mock_news = mocker.patch("tools.private.release.backport_prepare.changelog_news")
    mock_det = mocker.patch(
        "tools.private.release.backport_prepare.determine_next_version"
    )
    mock_det.side_effect = ["1.7.2", "1.8.1"]
    mock_git.cherry_pick.side_effect = [Exception("Conflict"), None]
    mock_news.update_changelog.side_effect = [Exception("Changelog error")]

    # Act
    result = BackportPrepare(args, mock_git, mock_gh).run()

    # Assert
    assert result == 0
    expected_body = (
        "* PR: #456\n"
        "* From version: 1.7\n"
        "* To version: 1.8\n"
        "\n"
        "## Tasks\n"
        "\n"
        "- [ ] Verify apply 1.7 | status=failed-conflict\n"
        "- [ ] Verify apply 1.8 | status=failed-changelog\n"
        "- [ ] Track Release 1.7.2\n"
        "- [ ] Track Release 1.8.1"
    )
    assert mock_gh.issues[123]["body"] == expected_body
