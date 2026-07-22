import dataclasses
from unittest.mock import MagicMock

import pytest

pytest_plugins = ["tests.tools.private.release.release_test_helper"]


@dataclasses.dataclass
class AutoPatchCmdHelpers:
    """Dataclass holding mocked command helpers."""

    run_cmd: MagicMock
    run_git: MagicMock
    run_gh: MagicMock


@pytest.fixture(name="mock_run_cmd")
def fixture_mock_run_cmd(mocker):
    """Fixture to patch shell.run_cmd and its imports in git and gh modules."""
    mock = mocker.patch("tools.private.release.shell.run_cmd")
    mocker.patch("tools.private.release.git.run_cmd", mock)
    mocker.patch("tools.private.release.gh.run_cmd", mock)
    return mock


@pytest.fixture(name="mock_run_git")
def fixture_mock_run_git(mocker):
    """Fixture to patch Git._run_git."""
    return mocker.patch("tools.private.release.git.Git._run_git")


@pytest.fixture(name="mock_run_gh")
def fixture_mock_run_gh(mocker):
    """Fixture to patch GitHub._run_gh."""
    return mocker.patch("tools.private.release.gh.GitHub._run_gh")


@pytest.fixture(name="auto_patch_cmd_helpers", autouse=True)
def fixture_auto_patch_cmd_helpers(mock_run_cmd, mock_run_git, mock_run_gh):
    """Automatically patches run_cmd, Git, and GitHub CLI helpers.

    This prevents tests from executing command line tools that could have
    side-effects.
    """
    return AutoPatchCmdHelpers(
        run_cmd=mock_run_cmd,
        run_git=mock_run_git,
        run_gh=mock_run_gh,
    )
