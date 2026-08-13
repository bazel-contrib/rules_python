"""Tests for .github/workflows/on_comment.py."""

import dataclasses
from pathlib import Path

import pytest
from on_comment import (
    _main,
    process_comment,
)


@dataclasses.dataclass
class GitHubActionEnv:
    output_file: Path
    env_file: Path

    def read_outputs(self) -> dict[str, str]:
        if not self.output_file.exists():
            return {}
        res = {}
        for line in self.output_file.read_text().splitlines():
            if "=" in line:
                k, v = line.split("=", 1)
                res[k] = v
        return res

    def read_env(self) -> dict[str, str]:
        if not self.env_file.exists():
            return {}
        res = {}
        for line in self.env_file.read_text().splitlines():
            if "=" in line:
                k, v = line.split("=", 1)
                res[k] = v
        return res


@pytest.fixture(name="gha_env", autouse=True)
def fixture_gha_env(tmp_path, monkeypatch) -> GitHubActionEnv:
    """Fixture that always sets GITHUB_OUTPUT and GITHUB_ENV environment variables."""
    out_file = tmp_path / "github_output.txt"
    env_file = tmp_path / "github_env.txt"
    monkeypatch.setenv("GITHUB_OUTPUT", str(out_file))
    monkeypatch.setenv("GITHUB_ENV", str(env_file))
    return GitHubActionEnv(output_file=out_file, env_file=env_file)


@pytest.fixture(name="mock_add_reaction", autouse=True)
def fixture_mock_add_reaction(mocker):
    """Fixture that mocks out _add_comment_reaction by default for all tests."""
    return mocker.patch("on_comment._add_comment_reaction")


def _run_comment(
    monkeypatch,
    comment_body: str,
    *,
    is_pr: str = "false",
    event_number: str = "100",
    has_release_label: str = "false",
    has_backport_label: str = "false",
    comment_id: str = "999",
    repo: str = "test/repo",
) -> None:
    monkeypatch.setenv("COMMENT_BODY", comment_body)
    monkeypatch.setenv("IS_PR", is_pr)
    monkeypatch.setenv("EVENT_NUMBER", event_number)
    monkeypatch.setenv("HAS_RELEASE_LABEL", has_release_label)
    monkeypatch.setenv("HAS_BACKPORT_LABEL", has_backport_label)
    monkeypatch.setenv("COMMENT_ID", comment_id)
    monkeypatch.setenv("GITHUB_REPOSITORY", repo)
    process_comment()


def test_release_issue_create_rc(monkeypatch, gha_env):
    _run_comment(
        monkeypatch,
        "/create-rc",
        has_release_label="true",
    )
    assert gha_env.read_outputs() == {
        "issue_number": "100",
        "command": "create-rc",
    }
    assert gha_env.read_env() == {"issue_number": "100"}


def test_release_issue_prepare_complete_with_arg(monkeypatch, gha_env):
    _run_comment(
        monkeypatch,
        "/prepare-complete #200",
        has_release_label="true",
    )
    assert gha_env.read_outputs() == {
        "issue_number": "100",
        "command": "prepare-complete",
        "pr_number": "200",
    }
    assert gha_env.read_env() == {"issue_number": "100"}


def test_release_issue_prepare_complete_no_arg(monkeypatch, gha_env):
    _run_comment(
        monkeypatch,
        "/prepare-complete",
        has_release_label="true",
    )
    assert gha_env.read_outputs() == {
        "issue_number": "100",
        "command": "prepare-complete",
    }
    assert gha_env.read_env() == {"issue_number": "100"}


def test_release_issue_create_release_branch(monkeypatch, gha_env):
    _run_comment(
        monkeypatch,
        "   /create-release-branch   ",
        has_release_label="true",
    )
    assert gha_env.read_outputs() == {
        "issue_number": "100",
        "command": "create-release-branch",
    }
    assert gha_env.read_env() == {"issue_number": "100"}


def test_release_issue_prepare(monkeypatch, gha_env):
    _run_comment(
        monkeypatch,
        "/prepare",
        has_release_label="true",
    )
    assert gha_env.read_outputs() == {
        "issue_number": "100",
        "command": "prepare",
    }
    assert gha_env.read_env() == {"issue_number": "100"}


def test_release_issue_process_backports(monkeypatch, gha_env):
    _run_comment(
        monkeypatch,
        "/process-backports",
        has_release_label="true",
    )
    assert gha_env.read_outputs() == {
        "issue_number": "100",
        "command": "process-backports",
    }
    assert gha_env.read_env() == {"issue_number": "100"}


def test_release_issue_add_backports(monkeypatch, gha_env):
    _run_comment(
        monkeypatch,
        "/add-backports 1, 2, 3",
        has_release_label="true",
    )
    assert gha_env.read_outputs() == {
        "issue_number": "100",
        "command": "add-backports",
        "backports": "1,2,3",
    }
    assert gha_env.read_env() == {"issue_number": "100"}


def test_release_issue_add_backports_hashes(monkeypatch, gha_env):
    _run_comment(
        monkeypatch,
        "/add-backports #123 #567",
        has_release_label="true",
    )
    assert gha_env.read_outputs() == {
        "issue_number": "100",
        "command": "add-backports",
        "backports": "#123,#567",
    }
    assert gha_env.read_env() == {"issue_number": "100"}


def test_release_issue_add_backports_empty(
    monkeypatch, gha_env, mock_add_reaction, capsys
):
    _run_comment(
        monkeypatch,
        "/add-backports",
        has_release_label="true",
        repo="bazel-contrib/rules_python",
        comment_id="789",
    )
    assert gha_env.read_outputs() == {
        "issue_number": "100",
        "command": "none",
    }
    assert gha_env.read_env() == {"issue_number": "100"}
    captured = capsys.readouterr()
    assert "Error: No PRs specified for add-backports." in captured.err
    mock_add_reaction.assert_called_once_with(
        repo="bazel-contrib/rules_python",
        comment_id="789",
        content="-1",
    )


def test_release_issue_promote(monkeypatch, gha_env):
    _run_comment(
        monkeypatch,
        "/promote",
        has_release_label="true",
    )
    assert gha_env.read_outputs() == {
        "issue_number": "100",
        "command": "promote",
    }
    assert gha_env.read_env() == {"issue_number": "100"}


def test_release_issue_unknown_comment(monkeypatch, gha_env):
    _run_comment(
        monkeypatch,
        "Just some ordinary comment",
        has_release_label="true",
    )
    assert gha_env.read_outputs() == {
        "issue_number": "100",
        "command": "none",
    }
    assert gha_env.read_env() == {"issue_number": "100"}


def test_release_issue_multiline_comment(monkeypatch, gha_env):
    body = "LGTM!\n/prepare\nWill test later."
    _run_comment(
        monkeypatch,
        body,
        has_release_label="true",
    )
    assert gha_env.read_outputs() == {
        "issue_number": "100",
        "command": "prepare",
    }
    assert gha_env.read_env() == {"issue_number": "100"}


def test_backport_issue_prepare(monkeypatch, gha_env):
    _run_comment(
        monkeypatch,
        "/prepare",
        has_backport_label="true",
    )
    assert gha_env.read_outputs() == {
        "issue_number": "100",
        "command": "backport-prepare",
    }
    assert gha_env.read_env() == {"issue_number": "100"}


def test_backport_issue_create_releases(monkeypatch, gha_env):
    _run_comment(
        monkeypatch,
        "/create-releases",
        has_backport_label="true",
    )
    assert gha_env.read_outputs() == {
        "issue_number": "100",
        "command": "backport-create-releases",
    }
    assert gha_env.read_env() == {"issue_number": "100"}


def test_backport_issue_unknown_comment(monkeypatch, gha_env):
    _run_comment(
        monkeypatch,
        "Random text",
        has_backport_label="true",
    )
    assert gha_env.read_outputs() == {
        "issue_number": "100",
        "command": "none",
    }
    assert gha_env.read_env() == {"issue_number": "100"}


def test_unlabeled_issue_ignored(monkeypatch, gha_env):
    _run_comment(
        monkeypatch,
        "/prepare",
        has_release_label="false",
        has_backport_label="false",
    )
    assert gha_env.read_outputs() == {
        "issue_number": "100",
        "command": "none",
    }
    assert gha_env.read_env() == {"issue_number": "100"}


def test_pr_backport(monkeypatch, gha_env):
    _run_comment(
        monkeypatch,
        "/backport",
        is_pr="true",
        event_number="300",
    )
    assert gha_env.read_outputs() == {
        "command": "pr-backport",
        "pr_number": "300",
    }
    assert gha_env.read_env() == {}


def test_pr_prepare_complete(monkeypatch, gha_env):
    _run_comment(
        monkeypatch,
        "/prepare-complete",
        is_pr="true",
        event_number="300",
    )
    assert gha_env.read_outputs() == {
        "command": "prepare-complete",
        "pr_number": "300",
    }
    assert gha_env.read_env() == {}


def test_pr_unknown_comment(monkeypatch, gha_env):
    _run_comment(
        monkeypatch,
        "Looks good!",
        is_pr="true",
        event_number="300",
    )
    assert gha_env.read_outputs() == {"command": "none"}
    assert gha_env.read_env() == {}


def test_main_cli_execution(monkeypatch, gha_env):
    monkeypatch.setenv("COMMENT_BODY", "/create-rc")
    monkeypatch.setenv("IS_PR", "false")
    monkeypatch.setenv("EVENT_NUMBER", "42")
    monkeypatch.setenv("HAS_RELEASE_LABEL", "true")
    monkeypatch.setenv("HAS_BACKPORT_LABEL", "false")

    with pytest.raises(SystemExit):
        _main()

    assert gha_env.read_outputs() == {
        "issue_number": "42",
        "command": "create-rc",
    }
    assert gha_env.read_env() == {"issue_number": "42"}
