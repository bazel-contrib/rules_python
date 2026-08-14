import dataclasses
import shutil
from pathlib import Path
from unittest.mock import MagicMock, patch

import pytest

from python.runfiles import runfiles
from tools.private.release.mock_gh import MockGitHub


@dataclasses.dataclass
class ReleaseToolEnv:
    """Environment setup for testing release tools.

    Attributes:
        git_root: The root path of the temporary Git repository workspace.
        github_output_file: Path to the mocked GITHUB_OUTPUT file.
    """

    git_root: Path
    github_output_file: Path


def _find_real_template_path() -> Path:
    r = runfiles.Create()
    path = r.Rlocation(
        "rules_python/.github/ISSUE_TEMPLATE/release_tracking_template.md"
    )
    if not path or not Path(path).is_file():
        raise FileNotFoundError(
            "Could not locate .github/ISSUE_TEMPLATE/release_tracking_template.md"
            f" in runfiles: {path}"
        )
    return Path(path)


@pytest.fixture(name="mock_git")
def fixture_mock_git():
    mock_git_inst = MagicMock()
    mock_git_inst.get_current_branch.return_value = None
    mock_git_inst.get_tags.return_value = []
    mock_git_inst.get_remote_tags.return_value = []
    mock_git_inst.status.return_value = ""
    mock_git_inst.branch_exists.return_value = False
    mock_git_inst.tag_exists.return_value = False

    with patch("tools.private.release.utils.Git", return_value=mock_git_inst):
        yield mock_git_inst


@pytest.fixture(name="mock_gh")
def fixture_mock_gh():
    return MockGitHub()


@pytest.fixture(name="release_tool_env")
def fixture_release_tool_env(tmp_path, monkeypatch):
    """Fixture providing a temp cwd with release template set up."""
    source_template = _find_real_template_path()
    monkeypatch.chdir(tmp_path)
    template_dir = tmp_path / ".github" / "ISSUE_TEMPLATE"
    template_dir.mkdir(parents=True, exist_ok=True)
    template_file = template_dir / "release_tracking_template.md"
    shutil.copy2(source_template, template_file)
    github_output_file = tmp_path / "github_output"
    monkeypatch.setenv("GITHUB_OUTPUT", str(github_output_file))
    yield ReleaseToolEnv(git_root=tmp_path, github_output_file=github_output_file)
