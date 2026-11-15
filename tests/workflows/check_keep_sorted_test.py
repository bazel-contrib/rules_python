"""Tests for .github/workflows/check_keep_sorted.py and CI configuration."""

from __future__ import annotations

import asyncio
import contextlib
import json
import os
import subprocess
from collections.abc import Iterator
from pathlib import Path
from typing import Any

import check_keep_sorted
import pytest
import yaml

from python.runfiles import runfiles


def _repo_file(rel_path: str) -> Path:
    return runfiles.CreateOrRaise().root() / f"rules_python/{rel_path}"


@contextlib.contextmanager
def _chdir(target: Path) -> Iterator[None]:
    prev = Path.cwd()
    os.chdir(target)
    try:
        yield
    finally:
        os.chdir(prev)


def _write_fake_keep_sorted(path: Path, body: str) -> Path:
    path.write_text(f"#!/usr/bin/env python3\n{body}\n", encoding="utf-8")
    path.chmod(0o755)
    return path


def _assert_ci_download_step_in_sync(
    *,
    repo_url: str,
    expected_hooks: list[str],
    job_id: str,
    step_id: str,
    url_template: str,
    archive_member: str = "",
) -> list[dict[str, Any]]:
    pre_commit = yaml.safe_load(
        _repo_file(".pre-commit-config.yaml").read_text(encoding="utf-8")
    )
    matching = [repo for repo in pre_commit["repos"] if repo.get("repo") == repo_url]
    assert len(matching) == 1
    rev = matching[0]["rev"]
    assert [hook["id"] for hook in matching[0]["hooks"]] == expected_hooks

    ci = yaml.safe_load(
        _repo_file(".github/workflows/ci.yaml").read_text(encoding="utf-8")
    )
    job = ci["jobs"][job_id]
    assert job["runs-on"] == "ubuntu-latest"
    steps = job["steps"]

    download_step = next(s for s in steps if s.get("id") == step_id)
    assert download_step["uses"] == "./.github/actions/download-tool"
    assert download_step["with"]["name"] == step_id
    assert download_step["with"].get("archive-member", "") == archive_member
    urls = [
        line.strip()
        for line in download_step["with"]["urls"].splitlines()
        if line.strip()
    ]
    assert urls == [url_template.format(rev=rev)]
    assert len(download_step["with"]["sha256"]) == 64
    return steps


def test_ci_workflow_uses_download_tool_in_sync_with_pre_commit() -> None:
    steps = _assert_ci_download_step_in_sync(
        repo_url="https://github.com/google/keep-sorted",
        expected_hooks=["keep-sorted"],
        job_id="keep_sorted",
        step_id="keep-sorted",
        url_template="https://github.com/google/keep-sorted/releases/download/{rev}/keep-sorted_linux_amd64",
    )

    check_step = next(s for s in steps if s.get("name") == "Check keep-sorted")
    assert check_step["env"] == {
        "KEEP_SORTED_BIN": "${{ steps.keep-sorted.outputs.path }}"
    }
    assert (
        check_step["run"]
        == './.github/workflows/check_keep_sorted.py -- "$KEEP_SORTED_BIN"'
    )


def test_ci_workflow_ifttt_lint_in_sync_with_pre_commit() -> None:
    steps = _assert_ci_download_step_in_sync(
        repo_url="https://github.com/simonepri/ifttt-lint",
        expected_hooks=["ifttt-lint", "ifttt-lint-diff"],
        job_id="ifttt_lint",
        step_id="ifttt-lint",
        url_template="https://github.com/simonepri/ifttt-lint/releases/download/{rev}/ifttt-lint-x86_64-unknown-linux-gnu.tar.gz",
        archive_member="ifttt-lint",
    )

    checkout_step = steps[0]
    assert checkout_step["uses"].startswith("actions/checkout@")
    assert checkout_step["with"]["fetch-depth"] == 0

    check_step = next(s for s in steps if s.get("name") == "Check ifttt-lint")
    assert check_step["env"] == {
        "IFTTT_LINT_BIN": "${{ steps.ifttt-lint.outputs.path }}"
    }
    assert check_step["run"] == "\"$IFTTT_LINT_BIN\" --vcs git '**/*'"

    diff_step = next(s for s in steps if s.get("name") == "Check ifttt-lint diff")
    assert diff_step["if"] == "github.event_name == 'pull_request'"
    assert diff_step["env"] == {
        "BASE_SHA": "${{ github.event.pull_request.base.sha }}",
        "HEAD_SHA": "${{ github.event.pull_request.head.sha }}",
        "IFTTT_LINT_BIN": "${{ steps.ifttt-lint.outputs.path }}",
    }
    assert (
        diff_step["run"]
        == '"$IFTTT_LINT_BIN" --vcs git --diff "${BASE_SHA}...${HEAD_SHA}"'
    )


def test_lint_files_formats_findings_across_concurrent_batches(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.setattr(check_keep_sorted, "FILES_PER_BATCH", 2)
    invocations_dir = tmp_path / "invocations"
    invocations_dir.mkdir()
    binary = _write_fake_keep_sorted(
        tmp_path / "keep-sorted",
        f"""
import json, os, pathlib, sys
args = sys.argv[1:]
assert args[:2] == ["--mode=lint", "--"], args
files = args[2:]
(pathlib.Path({str(invocations_dir)!r}) / str(os.getpid())).write_text("\\n".join(files))
findings = []
if "b.py" in files:
    findings.append({{"path": "b.py", "lines": {{"start": 10, "end": 14}}, "message": "These lines are out of order."}})
if "a.bzl" in files:
    findings.append({{"path": "a.bzl", "lines": {{"start": 5, "end": 5}}, "message": "Unmatched directive."}})
if findings:
    print(json.dumps(findings))
    sys.exit(1)
""",
    )

    failures = asyncio.run(
        check_keep_sorted.lint_files(binary, tmp_path, ["b.py", "c.py", "a.bzl"])
    )
    assert len(list(invocations_dir.iterdir())) == 2
    assert failures == [
        "b.py:10-14: These lines are out of order.",
        "a.bzl:5: Unmatched directive.",
    ]


def test_lint_files_fails_closed_on_non_json_error(tmp_path: Path) -> None:
    binary = _write_fake_keep_sorted(
        tmp_path / "keep-sorted",
        """
import sys
sys.stderr.write("fatal flag error\\n")
sys.exit(2)
""",
    )

    with pytest.raises(RuntimeError, match="fatal flag error"):
        asyncio.run(check_keep_sorted.lint_files(binary, tmp_path, ["a.py"]))


def test_end_to_end_git_tracked_files_success_and_sorted_failures(
    tmp_path: Path, capsys: pytest.CaptureFixture[str]
) -> None:
    repo = tmp_path / "repo"
    repo.mkdir()
    (repo / "z.py").write_text("z\n", encoding="utf-8")
    (repo / "a.py").write_text("a\n", encoding="utf-8")
    (repo / "link.py").symlink_to("a.py")
    subprocess.run(["git", "init", "--quiet"], cwd=repo, check=True)
    subprocess.run(["git", "add", "a.py", "z.py", "link.py"], cwd=repo, check=True)

    ok_bin = _write_fake_keep_sorted(
        tmp_path / "keep-sorted-ok",
        """
import sys
# Symlinks must be filtered out before invoking keep-sorted.
assert "link.py" not in sys.argv
sys.exit(0)
""",
    )
    fail_bin = _write_fake_keep_sorted(
        tmp_path / "keep-sorted-fail",
        f"""
import json, sys
print(json.dumps([
    {json.dumps({"path": "z.py", "lines": {"start": 2, "end": 4}, "message": "These lines are out of order."})},
    {json.dumps({"path": "a.py", "lines": {"start": 9, "end": 9}, "message": "Unmatched directive."})},
]))
sys.exit(1)
""",
    )

    with _chdir(repo):
        assert check_keep_sorted.main([str(ok_bin)]) == 0
        captured = capsys.readouterr()
        assert "Checked 2 tracked files" in captured.out
        assert captured.err == ""

        assert check_keep_sorted.main([str(fail_bin)]) == 1
        captured = capsys.readouterr()
        assert captured.out == ""
        assert captured.err.splitlines() == [
            "a.py:9: Unmatched directive.",
            "z.py:2-4: These lines are out of order.",
        ]
