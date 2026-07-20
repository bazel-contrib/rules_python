from unittest.mock import patch

import pytest

from tools.private.release.gh import GitHub


@pytest.fixture(name="gh")
def fixture_gh():
    return GitHub("my-owner/my-repo")


@patch("tools.private.release.gh.run_cmd")
def test_resolve_pr_number_digit(mock_run_cmd, gh):
    # 124 and #125 should resolve immediately without running command
    assert gh.resolve_pr_number("124") == 124
    assert gh.resolve_pr_number("#125") == 125
    mock_run_cmd.assert_not_called()


@patch("tools.private.release.gh.run_cmd")
def test_resolve_pr_number_url_simple(mock_run_cmd, gh):
    url = "https://github.com/my-owner/my-repo/pull/126"
    # Should resolve via regex without calling gh
    result = gh.resolve_pr_number(url)
    assert result == 126
    mock_run_cmd.assert_not_called()


@patch("tools.private.release.gh.run_cmd")
def test_resolve_pr_number_url_with_subpath(mock_run_cmd, gh):
    url = "https://github.com/my-owner/my-repo/pull/126/files"
    # Should resolve via regex without calling gh
    result = gh.resolve_pr_number(url)
    assert result == 126
    mock_run_cmd.assert_not_called()


@patch("tools.private.release.gh.run_cmd")
def test_resolve_pr_number_url_with_query(mock_run_cmd, gh):
    url = "https://github.com/my-owner/my-repo/pull/126/files?w=1"
    # Should resolve via regex without calling gh
    result = gh.resolve_pr_number(url)
    assert result == 126
    mock_run_cmd.assert_not_called()


@patch("tools.private.release.gh.run_cmd")
def test_resolve_pr_number_url_other_repo(mock_run_cmd, gh):
    # URL for a different repo should fail immediately without calling gh
    url = "https://github.com/other-owner/other-repo/pull/126"
    with pytest.raises(ValueError, match="URL is not for the configured repository"):
        gh.resolve_pr_number(url)
    mock_run_cmd.assert_not_called()


@patch("tools.private.release.gh.run_cmd")
def test_resolve_pr_number_invalid_ref(mock_run_cmd, gh):
    # Invalid reference (not number, not URL) should fail
    with pytest.raises(ValueError, match="Could not resolve PR reference"):
        gh.resolve_pr_number("invalid-ref")
    mock_run_cmd.assert_not_called()
