import dataclasses
from pathlib import Path
from unittest.mock import MagicMock, patch

import pytest

from tools.private.release.mock_gh import MockGitHub


@dataclasses.dataclass
class ReleaseToolEnv:
    """Environment setup for testing release tools.

    Attributes:
        git_root: The root path of the temporary Git repository workspace.
    """

    git_root: Path


DEFAULT_RELEASE_TEMPLATE_CONTENT = (
    "template content\n"
    "- [ ] Prepare Release\n"
    "- [ ] Tag RC0\n"
    "- [ ] Tag Final\n"
    "\n"
    "## Backports\n"
)


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
    monkeypatch.chdir(tmp_path)
    template_dir = tmp_path / ".github" / "ISSUE_TEMPLATE"
    template_dir.mkdir(parents=True, exist_ok=True)
    template_file = template_dir / "release_tracking_template.md"
    template_file.write_text(DEFAULT_RELEASE_TEMPLATE_CONTENT, encoding="utf-8")
    yield ReleaseToolEnv(git_root=tmp_path)
