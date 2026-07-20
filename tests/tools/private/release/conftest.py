import pytest

pytest_plugins = ["tests.tools.private.release.release_test_helper"]


@pytest.fixture(name="auto_patch_cmd_helpers", autouse=True)
def fixture_auto_patch_cmd_helpers(mocker):
    """Automatically patches run_cmd, Git, and GitHub CLI helpers.

    This prevents tests from executing command line tools that could have
    side-effects.
    """
    mock_run_cmd = mocker.patch("tools.private.release.shell.run_cmd")
    mocker.patch("tools.private.release.git.run_cmd", mock_run_cmd)
    mocker.patch("tools.private.release.gh.run_cmd", mock_run_cmd)
    mock_run_git = mocker.patch("tools.private.release.git.Git._run_git")
    mock_run_gh = mocker.patch("tools.private.release.gh.GitHub._run_gh")
    return {
        "run_cmd": mock_run_cmd,
        "run_git": mock_run_git,
        "run_gh": mock_run_gh,
    }
