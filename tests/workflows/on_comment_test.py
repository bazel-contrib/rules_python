"""Tests for .github/workflows/on_comment.py."""

import dataclasses
import json
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

    def read_env(self) -> dict[str, str]:
        if not self.env_file.exists():
            return {}
        res = {}
        for line in self.env_file.read_text().splitlines():
            if "=" in line:
                k, v = line.split("=", 1)
                res[k] = v
        return res

    def set_event(
        self,
        *,
        issue_number: int | str = 4175,
        comment_id: int | str = 5772601429,
        comment_url: str = "",
        repo: str = "bazel-contrib/rules_python",
        author_association: str = "OWNER",
        user_login: str = "test-owner",
    ) -> None:
        comment: dict[str, object] = {
            k: v
            for k, v in [
                ("id", comment_id),
                ("html_url", comment_url),
                ("author_association", author_association),
            ]
            if v
        }
        if user_login:
            comment["user"] = {"login": user_login}
        payload = {
            "issue": {"number": issue_number} if issue_number else {},
            "comment": comment,
            "repository": {"full_name": repo} if repo else {},
        }
        self.event_file.write_text(json.dumps(payload), encoding="utf-8")


@pytest.fixture(name="gha_env", autouse=True)
def fixture_gha_env(tmp_path, monkeypatch) -> GitHubActionEnv:
    """Fixture that sets GITHUB_OUTPUT, GITHUB_ENV, and GITHUB_EVENT_PATH."""
    out_file = tmp_path / "github_output.txt"
    env_file = tmp_path / "github_env.txt"
    event_file = tmp_path / "github_event.json"
    monkeypatch.setenv("GITHUB_OUTPUT", str(out_file))
    monkeypatch.setenv("GITHUB_ENV", str(env_file))
    monkeypatch.setenv("GITHUB_EVENT_PATH", str(event_file))
    env = GitHubActionEnv(
        output_file=out_file,
        env_file=env_file,
        event_file=event_file,
    )
    env.set_event()
    return env


@pytest.fixture(name="mock_add_reaction", autouse=True)
def fixture_mock_add_reaction(mocker):
    """Fixture that mocks out _add_comment_reaction by default for all tests."""
    return mocker.patch("on_comment._add_comment_reaction")


@pytest.fixture(name="mock_post_comment", autouse=True)
def fixture_mock_post_comment(mocker):
    """Fixture that mocks out _post_issue_comment by default for all tests."""
    return mocker.patch("on_comment._post_issue_comment")


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
) -> int:
    monkeypatch.setenv("COMMENT_BODY", comment_body)
    monkeypatch.setenv("IS_PR", is_pr)
    monkeypatch.setenv("EVENT_NUMBER", event_number)
    monkeypatch.setenv("HAS_RELEASE_LABEL", has_release_label)
    monkeypatch.setenv("HAS_BACKPORT_LABEL", has_backport_label)
    monkeypatch.setenv("COMMENT_ID", comment_id)
    monkeypatch.setenv("GITHUB_REPOSITORY", repo)
    return process_comment()


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


def test_release_issue_backport(monkeypatch, gha_env):
    _run_comment(
        monkeypatch,
        "/backport 1, 2, 3",
        has_release_label="true",
    )
    assert gha_env.read_outputs() == {
        "issue_number": "100",
        "command": "add-backports",
        "backports": "1,2,3",
    }
    assert gha_env.read_env() == {"issue_number": "100"}


def test_release_issue_backport_hashes(monkeypatch, gha_env):
    _run_comment(
        monkeypatch,
        "/backport #123 #567",
        has_release_label="true",
    )
    assert gha_env.read_outputs() == {
        "issue_number": "100",
        "command": "add-backports",
        "backports": "#123,#567",
    }
    assert gha_env.read_env() == {"issue_number": "100"}


def test_release_issue_backport_empty(monkeypatch, gha_env, mock_add_reaction, capsys):
    _run_comment(
        monkeypatch,
        "/backport",
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
    assert "::error::No PRs specified for backport." in captured.out
    mock_add_reaction.assert_called_once_with(
        repo="bazel-contrib/rules_python",
        comment_id="789",
        content="-1",
    )


def test_release_issue_sync_changelog(monkeypatch, gha_env):
    _run_comment(
        monkeypatch,
        "/sync-changelog",
        has_release_label="true",
    )
    assert gha_env.read_outputs() == {
        "issue_number": "100",
        "command": "sync-changelog",
    }
    assert gha_env.read_env() == {"issue_number": "100"}


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


def test_pr_backports_plural_alias(monkeypatch, gha_env):
    _run_comment(
        monkeypatch,
        "/backports",
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


def test_report_failure_with_command_and_urls(
    monkeypatch, gha_env, mock_add_reaction, mock_post_comment
):
    comment_url = (
        "https://github.com/bazel-contrib/rules_python/issues/4175"
        "#issuecomment-5772601429"
    )
    run_url = "https://github.com/bazel-contrib/rules_python/actions/runs/35698664041"
    gha_env.set_event(
        issue_number=4175,
        comment_id=5772601429,
        comment_url=comment_url,
        repo="bazel-contrib/rules_python",
    )
    monkeypatch.setenv("COMMAND", "create-rc")
    monkeypatch.setenv("GITHUB_RUN_ID", "35698664041")
    monkeypatch.setenv("GITHUB_SERVER_URL", "https://github.com")

    assert process_comment(report_failure=True) == 0

    mock_add_reaction.assert_called_once_with(
        repo="bazel-contrib/rules_python",
        comment_id="5772601429",
        content="-1",
    )
    mock_post_comment.assert_called_once_with(
        repo="bazel-contrib/rules_python",
        issue_number="4175",
        body=(
            f"Workflow failed for command `create-rc` ([comment]({comment_url})).\n\n"
            f"See [workflow run]({run_url}) for logs."
        ),
    )


def test_report_failure_without_command_or_urls(
    monkeypatch, gha_env, mock_add_reaction, mock_post_comment
):
    gha_env.set_event(
        issue_number=4175,
        comment_id="",
        comment_url="",
        repo="bazel-contrib/rules_python",
    )
    monkeypatch.setenv("COMMAND", "")
    monkeypatch.delenv("GITHUB_RUN_ID", raising=False)

    assert process_comment(report_failure=True) == 0

    mock_add_reaction.assert_not_called()
    mock_post_comment.assert_called_once_with(
        repo="bazel-contrib/rules_python",
        issue_number="4175",
        body=(
            "Workflow failed while processing comment.\n\n"
            "See workflow logs for details."
        ),
    )


def test_report_failure_missing_env(monkeypatch, gha_env, mock_post_comment, capsys):
    gha_env.set_event(issue_number="", comment_id="", repo="")
    monkeypatch.setenv("EVENT_NUMBER", "")
    monkeypatch.setenv("GITHUB_REPOSITORY", "")

    assert process_comment(report_failure=True) == 1
    mock_post_comment.assert_not_called()
    captured = capsys.readouterr()
    assert "::error::Issue number and repository are required" in captured.out


def test_main_cli_report_failure(
    monkeypatch, gha_env, mock_add_reaction, mock_post_comment
):
    gha_env.set_event(
        issue_number=42,
        comment_id=111,
        repo="bazel-contrib/rules_python",
    )
    monkeypatch.setenv("COMMAND", "promote")
    monkeypatch.setenv("GITHUB_RUN_ID", "99999")

    with pytest.raises(SystemExit) as exc_info:
        _main(["--report-failure"])

    assert exc_info.value.code == 0
    mock_add_reaction.assert_called_once_with(
        repo="bazel-contrib/rules_python",
        comment_id="111",
        content="-1",
    )
    mock_post_comment.assert_called_once()


def test_allowed_user_pr_backport(monkeypatch, gha_env):
    monkeypatch.setattr(
        "on_comment._BACKPORT_ALLOWED_USERS", frozenset({"allowed-user"})
    )
    gha_env.set_event(author_association="CONTRIBUTOR", user_login="allowed-user")
    rc = _run_comment(
        monkeypatch,
        "/backport",
        is_pr="true",
        event_number="300",
    )
    assert rc == 0
    assert gha_env.read_outputs() == {
        "command": "pr-backport",
        "pr_number": "300",
    }


def test_allowed_user_release_issue_backport(monkeypatch, gha_env):
    monkeypatch.setattr(
        "on_comment._BACKPORT_ALLOWED_USERS", frozenset({"allowed-user"})
    )
    gha_env.set_event(author_association="NONE", user_login="allowed-user")
    rc = _run_comment(
        monkeypatch,
        "/backport #123 #456",
        has_release_label="true",
    )
    assert rc == 0
    assert gha_env.read_outputs() == {
        "issue_number": "100",
        "command": "add-backports",
        "backports": "#123,#456",
    }


@pytest.mark.parametrize(
    "comment_body,is_pr,has_release_label,has_backport_label,expected_cmd",
    [
        ("/create-rc", "false", "true", "false", "create-rc"),
        ("/prepare", "false", "true", "false", "prepare"),
        ("/promote", "false", "true", "false", "promote"),
        ("/prepare-complete", "true", "false", "false", "prepare-complete"),
        ("/prepare", "false", "false", "true", "backport-prepare"),
        ("/create-releases", "false", "false", "true", "backport-create-releases"),
    ],
)
def test_allowed_user_disallowed_other_commands(
    monkeypatch,
    gha_env,
    capsys,
    comment_body,
    is_pr,
    has_release_label,
    has_backport_label,
    expected_cmd,
):
    monkeypatch.setattr(
        "on_comment._BACKPORT_ALLOWED_USERS", frozenset({"allowed-user"})
    )
    gha_env.set_event(author_association="CONTRIBUTOR", user_login="allowed-user")
    rc = _run_comment(
        monkeypatch,
        comment_body,
        is_pr=is_pr,
        has_release_label=has_release_label,
        has_backport_label=has_backport_label,
    )
    assert rc == 1
    captured = capsys.readouterr()
    assert (
        f"::error::User 'allowed-user' (association: 'CONTRIBUTOR') is not"
        f" allowed to trigger command '{expected_cmd}'."
    ) in captured.out


def test_unauthorized_user_disallowed_backport(monkeypatch, gha_env, capsys):
    gha_env.set_event(author_association="CONTRIBUTOR", user_login="random-user")
    rc = _run_comment(
        monkeypatch,
        "/backport",
        is_pr="true",
        event_number="300",
    )
    assert rc == 1
    captured = capsys.readouterr()
    assert (
        "::error::User 'random-user' (association: 'CONTRIBUTOR') is not"
        " allowed to trigger command 'pr-backport'."
    ) in captured.out


@pytest.mark.parametrize("association", ["OWNER", "MEMBER", "COLLABORATOR"])
def test_maintainer_associations_allowed_arbitrary_commands(
    monkeypatch, gha_env, association
):
    gha_env.set_event(author_association=association, user_login="maintainer")
    rc = _run_comment(
        monkeypatch,
        "/promote",
        has_release_label="true",
    )
    assert rc == 0
    assert gha_env.read_outputs() == {
        "issue_number": "100",
        "command": "promote",
    }


def test_non_command_comment_by_non_member_succeeds(monkeypatch, gha_env):
    gha_env.set_event(author_association="NONE", user_login="some-user")
    rc = _run_comment(
        monkeypatch,
        "Just an ordinary comment",
        is_pr="true",
        event_number="300",
    )
    assert rc == 0
    assert gha_env.read_outputs() == {"command": "none"}
