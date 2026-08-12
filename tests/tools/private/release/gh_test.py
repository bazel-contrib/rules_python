import subprocess

import pytest

from tools.private.release import shell
from tools.private.release.gh import (
    GetPrError,
    GitHub,
    InvalidPrRefError,
)
from tools.private.release.git import Git

pytest_plugins = ["tests.tools.private.release.release_test_helper"]


@pytest.fixture(name="gh")
def fixture_gh():
    return GitHub("my-owner/my-repo")


def test_resolve_pr_number_digit(mocker, gh):
    mock_run_cmd = mocker.patch("tools.private.release.gh.run_cmd")
    # 124 and #125 should resolve immediately without running command
    assert gh.resolve_pr_number("124") == 124
    assert gh.resolve_pr_number("#125") == 125
    mock_run_cmd.assert_not_called()


def test_resolve_pr_number_url_simple(mocker, gh):
    mock_run_cmd = mocker.patch("tools.private.release.gh.run_cmd")
    url = "https://github.com/my-owner/my-repo/pull/126"
    # Should resolve via regex without calling gh
    result = gh.resolve_pr_number(url)
    assert result == 126
    mock_run_cmd.assert_not_called()


def test_resolve_pr_number_url_with_subpath(mocker, gh):
    mock_run_cmd = mocker.patch("tools.private.release.gh.run_cmd")
    url = "https://github.com/my-owner/my-repo/pull/126/files"
    # Should resolve via regex without calling gh
    result = gh.resolve_pr_number(url)
    assert result == 126
    mock_run_cmd.assert_not_called()


def test_resolve_pr_number_url_with_query(mocker, gh):
    mock_run_cmd = mocker.patch("tools.private.release.gh.run_cmd")
    url = "https://github.com/my-owner/my-repo/pull/126/files?w=1"
    # Should resolve via regex without calling gh
    result = gh.resolve_pr_number(url)
    assert result == 126
    mock_run_cmd.assert_not_called()


def test_resolve_pr_number_url_other_repo(mocker, gh):
    mock_run_cmd = mocker.patch("tools.private.release.gh.run_cmd")
    # URL for a different repo should fail immediately without calling gh
    url = "https://github.com/other-owner/other-repo/pull/126"
    with pytest.raises(
        InvalidPrRefError, match="URL is not for the configured repository"
    ):
        gh.resolve_pr_number(url)
    mock_run_cmd.assert_not_called()


def test_resolve_pr_number_invalid(mocker, gh):
    mock_run_cmd = mocker.patch("tools.private.release.gh.run_cmd")
    with pytest.raises(InvalidPrRefError, match="Could not resolve PR reference"):
        gh.resolve_pr_number("invalid-ref")
    mock_run_cmd.assert_not_called()


def test_auto_patched_helpers_prevent_real_execution(auto_patch_cmd_helpers):
    # Calling run_cmd directly hits the mock
    shell.run_cmd("echo", "test")
    auto_patch_cmd_helpers.run_cmd.assert_called_with("echo", "test")

    # Git._run_git hits the mock
    git = Git(".")
    git._run_git("status")
    auto_patch_cmd_helpers.run_git.assert_called_with("status")

    # GitHub._run_gh hits the mock
    gh_obj = GitHub("foo/bar")
    gh_obj._run_gh("issue", "list")
    auto_patch_cmd_helpers.run_gh.assert_called_with("issue", "list")


def test_update_issue_body(gh, auto_patch_cmd_helpers):
    captured_body = {}

    def mock_run(*args, **kwargs):
        for arg in args:
            if isinstance(arg, str) and arg.startswith("--body-file="):
                path = arg.split("=", 1)[1]
                with open(path, encoding="utf-8") as f:
                    captured_body["content"] = f.read()
        return None

    auto_patch_cmd_helpers.run_gh.side_effect = mock_run
    gh.update_issue_body(123, "new body content")
    auto_patch_cmd_helpers.run_gh.assert_called_once()
    assert captured_body["content"] == "new body content"


def test_get_pr_files(gh, auto_patch_cmd_helpers):
    auto_patch_cmd_helpers.run_gh.return_value = (
        '{"files": [{"path": "news/123.added.md"}, {"path": "python/foo.py"}]}'
    )
    files = gh.get_pr_files(123)
    assert files == ["news/123.added.md", "python/foo.py"]
    auto_patch_cmd_helpers.run_gh.assert_called_with(
        "pr",
        "view",
        "123",
        "--json=files",
        "--repo=my-owner/my-repo",
        check=True,
        capture_output=True,
    )


def test_get_pr_files_not_found(gh, auto_patch_cmd_helpers):
    auto_patch_cmd_helpers.run_gh.side_effect = subprocess.CalledProcessError(1, ["gh"])
    with pytest.raises(GetPrError, match="Failed to get PR #123 on my-owner/my-repo"):
        gh.get_pr_files(123)
