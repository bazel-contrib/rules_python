import subprocess

import pytest

from tools.private.release.git import Git

pytest_plugins = ["tests.tools.private.release.release_test_helper"]


@pytest.fixture(name="git_obj")
def fixture_git_obj(mocker):
    git = Git(".")
    git.mock_run_git = mocker.patch.object(git, "_run_git")
    return git


def test_checkout_simple(git_obj):
    git_obj.checkout("my-branch")
    git_obj.mock_run_git.assert_called_once_with(
        "checkout", "my-branch", capture_output=False
    )


def test_checkout_track_remote_new_branch(mocker, git_obj):
    mock_branch_exists = mocker.patch(
        "tools.private.release.git.Git.branch_exists", return_value=False
    )

    git_obj.checkout("my-branch", track_remote="origin")

    mock_branch_exists.assert_called_once_with("my-branch")
    git_obj.mock_run_git.assert_called_once_with(
        "checkout", "--track", "origin/my-branch", capture_output=False
    )


def test_checkout_track_remote_existing_branch(mocker, git_obj):
    mock_branch_exists = mocker.patch(
        "tools.private.release.git.Git.branch_exists", return_value=True
    )
    mock_reset_hard = mocker.patch("tools.private.release.git.Git.reset_hard")

    git_obj.checkout("my-branch", track_remote="origin")

    mock_branch_exists.assert_called_once_with("my-branch")
    git_obj.mock_run_git.assert_called_once_with(
        "checkout", "my-branch", capture_output=False
    )
    mock_reset_hard.assert_called_once_with(reset_to="origin/my-branch")


def test_fetch_default(git_obj):
    git_obj.fetch()
    git_obj.mock_run_git.assert_called_once_with(
        "fetch", "origin", capture_output=False
    )


def test_fetch_custom_remote(git_obj):
    git_obj.fetch("upstream")
    git_obj.mock_run_git.assert_called_once_with(
        "fetch", "upstream", capture_output=False
    )


def test_fetch_with_refspec(git_obj):
    git_obj.fetch("origin", refspec="my-branch")
    git_obj.mock_run_git.assert_called_once_with(
        "fetch", "origin", "my-branch", capture_output=False
    )


def test_fetch_with_tags_and_force(git_obj):
    git_obj.fetch("origin", tags=True, force=True)
    git_obj.mock_run_git.assert_called_once_with(
        "fetch", "origin", "--tags", "--force", capture_output=False
    )


def test_fetch_all_options(git_obj):
    git_obj.fetch("origin", refspec="my-branch", tags=True, force=True)
    git_obj.mock_run_git.assert_called_once_with(
        "fetch", "origin", "my-branch", "--tags", "--force", capture_output=False
    )


def test_get_modified_files(git_obj):
    git_obj.mock_run_git.return_value = "file1.txt\nfile2.py\n\n"
    files = git_obj.get_modified_files("HEAD")
    git_obj.mock_run_git.assert_called_once_with(
        "show", "--name-only", "--format=", "HEAD"
    )
    assert files == ["file1.txt", "file2.py"]


def test_get_modified_files_empty(git_obj):
    git_obj.mock_run_git.return_value = ""
    files = git_obj.get_modified_files("HEAD")
    assert files == []


def test_diff_has_changes(git_obj):
    git_obj.mock_run_git.return_value = "some diff output"
    output = git_obj.diff()
    git_obj.mock_run_git.assert_called_once_with("diff")
    assert output == "some diff output"


def test_diff_empty(git_obj):
    git_obj.mock_run_git.return_value = ""
    output = git_obj.diff()
    git_obj.mock_run_git.assert_called_once_with("diff")
    assert output == ""


def test_apply(git_obj):
    git_obj.apply("patch.patch")
    git_obj.mock_run_git.assert_called_once_with(
        "apply", "patch.patch", capture_output=False
    )


def test_apply_check_clean(git_obj):
    git_obj.mock_run_git.return_value = ""
    result = git_obj.apply_check("patch.patch")
    git_obj.mock_run_git.assert_called_once_with(
        "apply", "--check", "patch.patch", capture_output=False
    )
    assert result is True


def test_apply_check_conflict(git_obj):
    git_obj.mock_run_git.side_effect = subprocess.CalledProcessError(
        1, ["git", "apply", "--check", "patch.patch"]
    )
    result = git_obj.apply_check("patch.patch")
    git_obj.mock_run_git.assert_called_once_with(
        "apply", "--check", "patch.patch", capture_output=False
    )
    assert result is False


def test_reset_hard_default(git_obj):
    git_obj.reset_hard()
    git_obj.mock_run_git.assert_called_once_with(
        "reset", "--hard", "HEAD", capture_output=False
    )


def test_reset_hard_custom(git_obj):
    git_obj.reset_hard(reset_to="my-commit")
    git_obj.mock_run_git.assert_called_once_with(
        "reset", "--hard", "my-commit", capture_output=False
    )
