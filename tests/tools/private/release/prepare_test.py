import argparse

from tools.private.release.prepare import Prepare

pytest_plugins = ["tests.tools.private.release.release_test_helper"]


def test_prepare_success_existing_issue(mocker, release_tool_env, mock_git, mock_gh):
    mocker.patch("tools.private.release.prepare.replace_version_next")
    mocker.patch("tools.private.release.prepare.changelog_news")

    # Arrange
    args = argparse.Namespace(version="2.0.0", issue=None, dry_run=False)
    mock_gh.create_issue(
        title="Release 2.0.0",
        body="- [ ] Prepare Release",
        labels=["type: release"],
    )  # Assigns issue 1001
    mock_git.status.side_effect = ["", "M  foo"]
    mock_git.branch_exists.return_value = False

    # Act
    result = Prepare(args, mock_git, mock_gh).run()

    # Assert
    assert result == 0
    assert 1002 in mock_gh.prs
    assert mock_gh.prs[1002]["title"] == "Prepare release v2.0.0"
    assert mock_gh.prs[1002]["body"] == "Work towards #1001"
    mock_git.add_modified_and_deleted.assert_called_once()


def test_prepare_success_create_issue(mocker, release_tool_env, mock_git, mock_gh):
    mocker.patch("tools.private.release.prepare.replace_version_next")
    mocker.patch("tools.private.release.prepare.changelog_news")

    # Arrange: release_tool_env sets up template_file automatically
    args = argparse.Namespace(version="2.0.0", issue=None, dry_run=False)
    mock_git.status.side_effect = ["", "M  foo"]
    mock_git.branch_exists.return_value = False

    # Act
    result = Prepare(args, mock_git, mock_gh).run()

    # Assert
    assert result == 0
    assert 1001 in mock_gh.issues
    assert mock_gh.issues[1001]["title"] == "Release 2.0.0"
    assert 1002 in mock_gh.prs
    assert mock_gh.prs[1002]["title"] == "Prepare release v2.0.0"
    assert mock_gh.prs[1002]["body"] == "Work towards #1001"
    mock_git.add_modified_and_deleted.assert_called_once()


def test_prepare_ambiguous_issue(mocker, release_tool_env, mock_git, mock_gh):
    mocker.patch("tools.private.release.prepare.replace_version_next")
    mocker.patch("tools.private.release.prepare.changelog_news")

    # Arrange
    args = argparse.Namespace(version="2.0.0", issue=None, dry_run=False)
    mock_gh.create_issue(
        title="Release 2.0.0", body="issue 1", labels=["type: release"]
    )
    mock_gh.create_issue(
        title="Release 2.0.0", body="issue 2", labels=["type: release"]
    )
    mock_git.status.side_effect = ["", "M  foo"]
    mock_git.branch_exists.return_value = False

    # Act
    result = Prepare(args, mock_git, mock_gh).run()

    # Assert
    assert result == 1
    mock_git.add_modified_and_deleted.assert_not_called()


def test_prepare_dry_run(mocker, release_tool_env, mock_git, mock_gh):
    mocker.patch("tools.private.release.prepare.replace_version_next")
    mocker.patch("tools.private.release.prepare.changelog_news")

    # Arrange
    args = argparse.Namespace(version="2.0.0", issue=None, dry_run=True)
    mock_gh.create_issue(title="Release 2.0.0", body="body", labels=["type: release"])
    mock_git.status.side_effect = [""]

    # Act
    result = Prepare(args, mock_git, mock_gh).run()

    # Assert
    assert result == 0
    mock_git.checkout.assert_not_called()
    mock_git.commit.assert_not_called()
    mock_git.push.assert_not_called()
    mock_git.fetch.assert_called_once()
    mock_git.add_modified_and_deleted.assert_not_called()


def test_prepare_use_associated_pr_from_tracking_issue(
    mocker, release_tool_env, mock_git, mock_gh
):
    mocker.patch("tools.private.release.prepare.replace_version_next")
    mocker.patch("tools.private.release.prepare.changelog_news")

    # Arrange
    args = argparse.Namespace(version="2.0.0", issue=None, dry_run=False)
    mock_gh.create_issue(
        title="Release 2.0.0",
        body="- [ ] Prepare Release | status=pending pr=#456",
        labels=["type: release"],
    )
    mock_git.status.side_effect = ["", ""]
    mock_git.branch_exists.return_value = True

    # Act
    result = Prepare(args, mock_git, mock_gh).run()

    # Assert
    assert result == 0
    mock_git.checkout.assert_called_once_with("prepare-2.0.0")
    mock_git.commit.assert_not_called()
    mock_git.push.assert_called_once_with(
        "origin", "prepare-2.0.0", set_upstream=True, force=True
    )
    updated_body = mock_gh.get_issue_body(1001)
    assert "pr=#456" in updated_body


def test_prepare_create_pr_when_none_associated(
    mocker, release_tool_env, mock_git, mock_gh
):
    mocker.patch("tools.private.release.prepare.replace_version_next")
    mocker.patch("tools.private.release.prepare.changelog_news")

    # Arrange
    args = argparse.Namespace(version="2.0.0", issue=None, dry_run=False)
    mock_gh.create_issue(
        title="Release 2.0.0",
        body="- [ ] Prepare Release",
        labels=["type: release"],
    )
    mock_git.status.side_effect = ["", ""]
    mock_git.branch_exists.return_value = True

    # Act
    result = Prepare(args, mock_git, mock_gh).run()

    # Assert
    assert result == 0
    mock_git.checkout.assert_called_once_with("prepare-2.0.0")
    mock_git.commit.assert_not_called()
    mock_git.push.assert_called_once_with(
        "origin", "prepare-2.0.0", set_upstream=True, force=True
    )
    updated_body = mock_gh.get_issue_body(1001)
    assert "pr=#1002" in updated_body


def test_prepare_reuse_existing_pr(mocker, release_tool_env, mock_git, mock_gh):
    mocker.patch("tools.private.release.prepare.replace_version_next")
    mocker.patch("tools.private.release.prepare.changelog_news")

    # Arrange
    args = argparse.Namespace(version="2.0.0", issue=None, dry_run=False)
    mock_gh.create_issue(
        title="Release 2.0.0",
        body="- [ ] Prepare Release",
        labels=["type: release"],
    )
    mock_gh.prs[456] = {
        "number": 456,
        "head": "prepare-2.0.0",
        "state": "OPEN",
        "url": "https://github.com/foo/bar/pull/456",
    }
    mock_git.status.side_effect = ["", ""]
    mock_git.branch_exists.return_value = True

    # Act
    result = Prepare(args, mock_git, mock_gh).run()

    # Assert
    assert result == 0
    mock_git.checkout.assert_called_once_with("prepare-2.0.0")
    mock_git.commit.assert_not_called()
    mock_git.push.assert_called_once_with(
        "origin", "prepare-2.0.0", set_upstream=True, force=True
    )
    updated_body = mock_gh.get_issue_body(1001)
    assert "pr=#456" in updated_body


def test_prepare_dry_run_no_issue(mocker, release_tool_env, mock_git, mock_gh):
    mocker.patch("tools.private.release.prepare.replace_version_next")
    mocker.patch("tools.private.release.prepare.changelog_news")

    # Arrange
    args = argparse.Namespace(version="2.0.0", issue=None, dry_run=True)
    mock_git.status.side_effect = [""]

    # Act
    result = Prepare(args, mock_git, mock_gh).run()

    # Assert
    assert result == 0
    mock_git.checkout.assert_not_called()
    mock_git.add_modified_and_deleted.assert_not_called()
