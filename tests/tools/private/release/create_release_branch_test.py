import argparse

from tools.private.release.create_release_branch import CreateReleaseBranch

pytest_plugins = ["tests.tools.private.release.release_test_helper"]


def test_create_release_branch_success(mock_git, mock_gh):
    # Arrange
    args = argparse.Namespace(issue=123, remote="my-remote")
    mock_gh.issues[123] = {
        "title": "Release 2.0.0",
        "body": """
## Checklist
- [x] Prepare Release | status=done pr=#122 commit=abcdef12
- [ ] Create Release branch | status=pending
""",
        "labels": ["type: release"],
    }
    mock_git.branch_exists.return_value = False
    mock_git.remote_branch_exists.return_value = False

    # Act
    result = CreateReleaseBranch(args, mock_git, mock_gh).run()

    # Assert
    assert result == 0
    mock_git.fetch.assert_called_once_with("my-remote")
    mock_git.checkout.assert_not_called()
    mock_git.push.assert_called_once_with(
        "my-remote", "abcdef12:refs/heads/release/2.0"
    )

    updated_body = mock_gh.get_issue_body(123)
    assert (
        "branch_url=https://github.com/bazel-contrib/rules_python/tree/release/2.0"
        in updated_body
    )
    assert "commit= abcdef12" in updated_body


def test_create_release_branch_prepare_not_done(mock_git, mock_gh):
    # Arrange
    args = argparse.Namespace(issue=123, remote="my-remote")
    mock_gh.issues[123] = {
        "title": "Release 2.0.0",
        "body": """
## Checklist
- [ ] Prepare Release | status=pending
- [ ] Create Release branch | status=pending
""",
        "labels": ["type: release"],
    }
    # Act
    result = CreateReleaseBranch(args, mock_git, mock_gh).run()

    # Assert
    assert result == 1
    mock_git.fetch.assert_not_called()
    mock_git.push.assert_not_called()


def test_create_release_branch_already_checked(mock_git, mock_gh):
    # Arrange
    args = argparse.Namespace(issue=123, remote="my-remote")
    mock_gh.issues[123] = {
        "title": "Release 2.0.0",
        "body": """
## Checklist
- [x] Prepare Release | status=done pr=#122 commit=abcdef12
- [x] Create Release branch | status=done branch=release/2.0 commit=abcdef12
""",
        "labels": ["type: release"],
    }
    # Act
    result = CreateReleaseBranch(args, mock_git, mock_gh).run()

    # Assert
    assert result == 0
    mock_git.fetch.assert_not_called()
    mock_git.push.assert_not_called()


def test_create_release_branch_already_exists_same_commit(mock_git, mock_gh):
    # Arrange
    args = argparse.Namespace(issue=123, remote="my-remote")
    mock_gh.issues[123] = {
        "title": "Release 2.0.0",
        "body": """
## Checklist
- [x] Prepare Release | status=done pr=#122 commit=abcdef12
- [ ] Create Release branch | status=pending
""",
        "labels": ["type: release"],
    }
    mock_git.remote_branch_exists.return_value = True
    mock_git.get_commit_sha.return_value = "abcdef12"

    # Act
    result = CreateReleaseBranch(args, mock_git, mock_gh).run()

    # Assert
    assert result == 0
    mock_git.fetch.assert_called_once_with("my-remote")
    mock_git.push.assert_not_called()


def test_create_release_branch_already_exists_fast_forward(mock_git, mock_gh):
    # Arrange
    args = argparse.Namespace(issue=123, remote="my-remote")
    mock_gh.issues[123] = {
        "title": "Release 2.0.0",
        "body": """
## Checklist
- [x] Prepare Release | status=done pr=#122 commit=abcdef12
- [ ] Create Release branch | status=pending
""",
        "labels": ["type: release"],
    }
    mock_git.remote_branch_exists.return_value = True
    mock_git.get_commit_sha.return_value = "oldcommit"
    mock_git.is_ancestor.return_value = True

    # Act
    result = CreateReleaseBranch(args, mock_git, mock_gh).run()

    # Assert
    assert result == 0
    mock_git.fetch.assert_called_once_with("my-remote")
    mock_git.push.assert_called_once_with(
        "my-remote", "abcdef12:refs/heads/release/2.0"
    )


def test_create_release_branch_already_exists_non_ff(mock_git, mock_gh):
    # Arrange
    args = argparse.Namespace(issue=123, remote="my-remote")
    mock_gh.issues[123] = {
        "title": "Release 2.0.0",
        "body": """
## Checklist
- [x] Prepare Release | status=done pr=#122 commit=abcdef12
- [ ] Create Release branch | status=pending
""",
        "labels": ["type: release"],
    }
    mock_git.remote_branch_exists.return_value = True
    mock_git.get_commit_sha.return_value = "othercommit"
    mock_git.is_ancestor.return_value = False

    # Act
    result = CreateReleaseBranch(args, mock_git, mock_gh).run()

    # Assert
    assert result == 1
    mock_git.fetch.assert_called_once_with("my-remote")
    mock_git.push.assert_not_called()
