"""Tests for .github/workflows/on_pr_closed.py."""

import dataclasses
import json
from pathlib import Path

import pytest
from on_pr_closed import (
    _main,
    process_pr_closed,
)


@dataclasses.dataclass
class GitHubActionEnv:
    output_file: Path
    event_file: Path

    def read_outputs(self) -> dict[str, str]:
        if not self.output_file.exists():
            return {}
        res = {}
        for line in self.output_file.read_text().splitlines():
            if "=" in line:
                k, v = line.split("=", 1)
                res[k] = v
        return res

    def set_event(
        self,
        *,
        pr_number: int = 123,
        merged: bool = True,
        labels: list[str] | None = None,
        repo: str = "bazel-contrib/rules_python",
    ) -> None:
        payload = {
            "pull_request": {
                "number": pr_number,
                "merged": merged,
                "labels": [{"name": label} for label in (labels or [])],
            },
            "repository": {
                "full_name": repo,
            },
        }
        self.event_file.write_text(json.dumps(payload), encoding="utf-8")


@pytest.fixture(name="gha_env", autouse=True)
def fixture_gha_env(tmp_path, monkeypatch) -> GitHubActionEnv:
    """Fixture that sets GITHUB_OUTPUT and GITHUB_EVENT_PATH environment variables."""
    out_file = tmp_path / "github_output.txt"
    event_file = tmp_path / "github_event.json"
    monkeypatch.setenv("GITHUB_OUTPUT", str(out_file))
    monkeypatch.setenv("GITHUB_EVENT_PATH", str(event_file))
    return GitHubActionEnv(output_file=out_file, event_file=event_file)


def test_pr_not_merged_ignored(gha_env):
    gha_env.set_event(pr_number=123, merged=False)
    process_pr_closed()
    assert gha_env.read_outputs() == {"command": "none"}


def test_sync_changelog_pr_merged(gha_env):
    gha_env.set_event(
        pr_number=123,
        merged=True,
        labels=["type: sync-changelog"],
    )
    process_pr_closed()
    assert gha_env.read_outputs() == {
        "command": "complete-sync-changelog",
        "pr_number": "123",
    }


def test_backport_candidate_pr_merged(mocker, gha_env):
    mocker.patch("on_pr_closed._check_active_release_issue", return_value=True)
    mocker.patch("on_pr_closed._check_pr_has_backport_comment", return_value=True)

    gha_env.set_event(
        pr_number=123,
        merged=True,
        labels=["type: bug"],
    )
    process_pr_closed()
    assert gha_env.read_outputs() == {
        "command": "process-backports",
        "pr_number": "123",
    }


def test_regular_pr_merged_no_backport(mocker, gha_env):
    mocker.patch("on_pr_closed._check_active_release_issue", return_value=True)
    mocker.patch("on_pr_closed._check_pr_has_backport_comment", return_value=False)

    gha_env.set_event(
        pr_number=123,
        merged=True,
        labels=["type: feature"],
    )
    process_pr_closed()
    assert gha_env.read_outputs() == {"command": "none"}


def test_backport_pr_no_active_release(mocker, gha_env):
    mocker.patch("on_pr_closed._check_active_release_issue", return_value=False)

    gha_env.set_event(
        pr_number=123,
        merged=True,
        labels=["type: bug"],
    )
    process_pr_closed()
    assert gha_env.read_outputs() == {"command": "none"}


def test_main_cli_execution(gha_env):
    gha_env.set_event(
        pr_number=42,
        merged=True,
        labels=["type: sync-changelog"],
    )

    with pytest.raises(SystemExit):
        _main()

    assert gha_env.read_outputs() == {
        "command": "complete-sync-changelog",
        "pr_number": "42",
    }
