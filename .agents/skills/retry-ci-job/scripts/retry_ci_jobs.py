#!/usr/bin/env python3
"""Retry failed Buildkite or GitHub Actions CI jobs, unblock manual steps, or rebuild builds.

Target input flags (mutually exclusive, one required):
  - `--pr <number>`: Pull request number (e.g. `--pr 4320`)
  - `--url <url>`: Buildkite build URL (`https://buildkite.com/<org>/<pipeline>/builds/<number>`)
    or GitHub Actions run/job URL
    (`https://github.com/<owner>/<repo>/actions/runs/<run_id>[/job/<job_id>]`)
  - `--buildkite-build <org/pipeline/number>`: Buildkite build identifier
  - `--buildkite-job-id <uuid>`: Individual Buildkite job UUID
  - `--github-job-id <id>`: Individual GitHub Actions job ID

Usage:
  ./.agents/skills/retry-ci-job/scripts/retry_ci_jobs.py --pr 4320
  ./.agents/skills/retry-ci-job/scripts/retry_ci_jobs.py --pr 4320 --unblock
  ./.agents/skills/retry-ci-job/scripts/retry_ci_jobs.py --pr 4320 --jobs "Build linux"
  ./.agents/skills/retry-ci-job/scripts/retry_ci_jobs.py --github-job-id 1234567890
  ./.agents/skills/retry-ci-job/scripts/retry_ci_jobs.py --buildkite-job-id 0190a1b2-c3d4
  ./.agents/skills/retry-ci-job/scripts/retry_ci_jobs.py --pr 4320 --rebuild
"""

from __future__ import annotations

import argparse
import enum
import json
import re
import subprocess
import sys
import time
from collections.abc import Mapping, Sequence
from dataclasses import dataclass

# ==============================================================================
# 1. Global variables / constants
# ==============================================================================

_DEFAULT_GH_REPO = "bazel-contrib/rules_python"
_DEFAULT_BK_PIPELINE = "bazel/rules-python-python"

_GH_ACTIONS_URL_RE = re.compile(
    r"github\.com/([^/]+/[^/]+)/actions/runs/(\d+)(?:/job/(\d+))?"
)
_BK_BUILD_URL_RE = re.compile(r"buildkite\.com/([^/]+/[^/]+)/builds/(\d+)")

# GitHub rejects `gh run rerun` while sibling matrix jobs in the workflow run are
# still executing; poll up to 15 minutes (60 * 15s) for the parent run to finish.
_GH_POLL_INTERVAL_SECONDS = 15
_GH_MAX_POLL_ATTEMPTS = 60

_FAILED_CHECK_STATES = frozenset(
    [
        # keep-sorted start
        "CANCELLED",
        "FAIL",
        "FAILURE",
        "STARTUP_FAILURE",
        "TIMED_OUT",
        # keep-sorted end
    ]
)

_FAILED_BK_JOB_STATES = frozenset(
    [
        # keep-sorted start
        "broken",
        "failed",
        "timed_out",
        # keep-sorted end
    ]
)

_BLOCKED_BK_JOB_STATES = frozenset(
    [
        # keep-sorted start
        "blocked",
        "blocked_failed",
        # keep-sorted end
    ]
)


# ==============================================================================
# 2. Flags / CLI arguments
# ==============================================================================


def _parse_args(argv: Sequence[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Retry failed Buildkite or GitHub Actions jobs individually, "
            "unblock Buildkite approval steps, or rebuild entire builds."
        )
    )
    target_group = parser.add_mutually_exclusive_group(required=True)
    target_group.add_argument(
        "--pr",
        type=int,
        default=0,
        help="Pull request number to inspect and retry",
    )
    target_group.add_argument(
        "--url",
        default="",
        help="Buildkite build URL or GitHub Actions workflow run/job URL",
    )
    target_group.add_argument(
        "--buildkite-build",
        default="",
        dest="buildkite_build",
        help="Buildkite build identifier (<org>/<pipeline>/<number> or <number>)",
    )
    target_group.add_argument(
        "--buildkite-job-id",
        default="",
        dest="buildkite_job_id",
        help="Specific Buildkite job UUID to retry individually",
    )
    target_group.add_argument(
        "--github-job-id",
        default="",
        dest="github_job_id",
        help="Specific GitHub Actions job ID to retry individually",
    )

    mode_group = parser.add_mutually_exclusive_group()
    mode_group.add_argument(
        "--jobs",
        default="",
        dest="job_name",
        help="Specific job name or regex pattern to retry individually",
    )
    mode_group.add_argument(
        "--rebuild",
        action="store_true",
        help="Rebuild the entire build afresh",
    )
    mode_group.add_argument(
        "--unblock",
        action="store_true",
        help=(
            "Unblock manual approval steps (e.g. .bazelci/presubmit.yml "
            "changes) via 'bk job unblock'"
        ),
    )
    return parser.parse_args(list(argv))


# ==============================================================================
# 3. Functions
# ==============================================================================


def _check_cli(cmd_name: str, install_url: str) -> None:
    try:
        subprocess.run(
            [cmd_name, "--version"],
            check=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
    except (OSError, subprocess.SubprocessError) as e:
        raise CiRetryError(
            f"❌ Error: '{cmd_name}' CLI is not installed or not in PATH.\n"
            f"Please install it from {install_url}"
        ) from e


def _extract_json_object(raw_output: str) -> dict[str, object]:
    if "{" not in raw_output:
        return {}
    json_str = raw_output[raw_output.find("{") : raw_output.rfind("}") + 1]
    parsed = json.loads(json_str)
    if isinstance(parsed, dict):
        return parsed
    return {}


def _extract_json_array(raw_output: str) -> list[dict[str, object]]:
    if "[" not in raw_output:
        return []
    json_str = raw_output[raw_output.find("[") : raw_output.rfind("]") + 1]
    parsed = json.loads(json_str)
    if isinstance(parsed, list):
        return parsed
    return []


def _get_pr_checks(pr_number: int) -> list[dict[str, object]]:
    _check_cli("gh", "https://cli.github.com/")
    cmd = [
        "gh",
        "pr",
        "checks",
        str(pr_number),
        "--json",
        "name,link,state,bucket",
    ]
    res = subprocess.run(cmd, capture_output=True, text=True)
    if "[" not in res.stdout:
        raise CiRetryError(
            f"❌ Error fetching PR checks for PR #{pr_number}: {res.stderr.strip()}"
        )
    return _extract_json_array(res.stdout)


def _matches_job_pattern(job_name: str, pattern: str) -> bool:
    if pattern.lower() in job_name.lower():
        return True
    try:
        return bool(re.search(pattern, job_name, re.IGNORECASE))
    except re.error:
        return False


def _is_check_failed(check: Mapping[str, object]) -> bool:
    state = str(check.get("state") or "").upper()
    bucket = str(check.get("bucket") or "").lower()
    return state in _FAILED_CHECK_STATES or bucket == "fail"


def _parse_github_actions_url(target: str) -> GitHubRunTarget | None:
    match = _GH_ACTIONS_URL_RE.search(target)
    if not match:
        return None
    return GitHubRunTarget(
        repo=match.group(1),
        run_id=match.group(2),
        job_id=match.group(3) or "",
    )


def _parse_buildkite_url(url: str) -> BuildkiteBuildTarget | None:
    clean_url = url.split("#")[0]
    match = _BK_BUILD_URL_RE.search(clean_url)
    if not match:
        return None
    return BuildkiteBuildTarget(
        pipeline=match.group(1),
        build_number=match.group(2),
    )


def _parse_buildkite_build_spec(spec: str) -> BuildkiteBuildTarget:
    clean_spec = spec.split("#")[0]
    parts = clean_spec.split("/")
    if len(parts) == 3:
        return BuildkiteBuildTarget(
            pipeline=f"{parts[0]}/{parts[1]}",
            build_number=parts[2],
        )
    if len(parts) == 2:
        return BuildkiteBuildTarget(
            pipeline=parts[0],
            build_number=parts[1],
        )
    if len(parts) == 1 and clean_spec:
        return BuildkiteBuildTarget(
            pipeline=_DEFAULT_BK_PIPELINE,
            build_number=clean_spec,
        )
    raise CiRetryError(
        f"❌ Error: Invalid Buildkite build identifier '{spec}'. "
        "Expected '<org>/<pipeline>/<number>' or '<number>'."
    )


def _resolve_mode(args: argparse.Namespace) -> OperationMode:
    if args.unblock:
        return OperationMode.UNBLOCK
    if args.rebuild:
        return OperationMode.REBUILD
    if args.job_name:
        return OperationMode.MATCH_JOBS
    return OperationMode.RETRY_FAILED


def _resolve_target(
    args: argparse.Namespace,
) -> (
    PrTarget
    | BuildkiteBuildTarget
    | BuildkiteJobTarget
    | GitHubRunTarget
    | GitHubJobTarget
):
    if args.pr:
        return PrTarget(pr_number=args.pr)
    if args.buildkite_job_id:
        return BuildkiteJobTarget(job_uuid=args.buildkite_job_id)
    if args.github_job_id:
        return GitHubJobTarget(repo=_DEFAULT_GH_REPO, job_id=args.github_job_id)
    if args.buildkite_build:
        return _parse_buildkite_build_spec(args.buildkite_build)
    if args.url:
        gh_run_target = _parse_github_actions_url(args.url)
        if gh_run_target:
            return gh_run_target
        bk_build_target = _parse_buildkite_url(args.url)
        if bk_build_target:
            return bk_build_target
        raise CiRetryError(
            f"❌ Error: Unsupported URL '{args.url}'. "
            "Expected a Buildkite build URL or GitHub Actions run/job URL."
        )
    raise CiRetryError("❌ Error: No target specified.")


# ==============================================================================
# 4. Classes
# ==============================================================================


class CiRetryError(Exception):
    """Raised when CLI prerequisites or target arguments are invalid."""


class OperationMode(enum.Enum):
    """Execution mode for retrying, unblocking, or rebuilding CI targets."""

    RETRY_FAILED = "retry_failed"
    UNBLOCK = "unblock"
    REBUILD = "rebuild"
    MATCH_JOBS = "match_jobs"


@dataclass(frozen=True)
class PrTarget:
    """Pull request number target."""

    pr_number: int


@dataclass(frozen=True)
class BuildkiteBuildTarget:
    """Buildkite pipeline and build number target."""

    pipeline: str
    build_number: str


@dataclass(frozen=True)
class BuildkiteJobTarget:
    """Individual Buildkite job UUID target."""

    job_uuid: str


@dataclass(frozen=True)
class GitHubRunTarget:
    """GitHub Actions workflow run (and optional job ID) target."""

    repo: str
    run_id: str
    job_id: str = ""


@dataclass(frozen=True)
class GitHubJobTarget:
    """Standalone numeric GitHub Actions job ID target."""

    repo: str
    job_id: str


class BuildkiteProvider:
    """Executes Buildkite job retries, manual step unblocks, and build rebuilds."""

    def _ensure_cli(self) -> None:
        _check_cli("bk", "https://github.com/buildkite/cli")

    def _view_build(self, target: BuildkiteBuildTarget) -> list[dict[str, object]]:
        self._ensure_cli()
        cmd = [
            "bk",
            "build",
            "view",
            target.build_number,
            "-p",
            target.pipeline,
            "--json",
        ]
        res = subprocess.run(cmd, capture_output=True, text=True, check=True)
        data = json.loads(res.stdout)
        jobs = data.get("jobs", []) if isinstance(data, dict) else []
        if isinstance(jobs, list):
            return jobs
        return []

    def retry_job_by_uuid(self, target: BuildkiteJobTarget) -> bool:
        self._ensure_cli()
        print(f"🚀 Retrying individual Buildkite job UUID: {target.job_uuid}")
        res = subprocess.run(["bk", "job", "retry", target.job_uuid])
        return res.returncode == 0

    def rebuild_build(self, target: BuildkiteBuildTarget) -> bool:
        self._ensure_cli()
        print(
            f"🚀 Rebuilding entire build #{target.build_number} "
            f"for pipeline: {target.pipeline}"
        )
        res = subprocess.run(
            [
                "bk",
                "build",
                "rebuild",
                target.build_number,
                "-p",
                target.pipeline,
                "--yes",
            ]
        )
        return res.returncode == 0

    def unblock_manual_jobs(
        self, jobs: Sequence[Mapping[str, object]]
    ) -> tuple[list[Mapping[str, object]], bool]:
        unblocked: list[Mapping[str, object]] = []
        all_ok = True
        for job in jobs:
            jstate = str(job.get("state") or "")
            is_manual_block = (
                job.get("type") == "manual" or job.get("unblockable") is True
            )
            jid = str(job.get("id") or "")
            if jid and jstate in _BLOCKED_BK_JOB_STATES and is_manual_block:
                jname = str(job.get("name") or job.get("label") or jid)
                print(f"🔓 Unblocking manual approval job '{jname}' (ID: {jid})...")
                res = subprocess.run(["bk", "job", "unblock", jid, "--no-input"])
                if res.returncode != 0:
                    all_ok = False
                unblocked.append(job)
        return unblocked, all_ok

    def retry_jobs_by_name(
        self,
        target: BuildkiteBuildTarget,
        job_pattern: str,
        fail_on_missing: bool = True,
    ) -> tuple[bool, bool]:
        """Retries Buildkite jobs matching `job_pattern`.

        Returns:
            Tuple of `(matched_any, all_succeeded)`.
        """
        try:
            jobs = self._view_build(target)
        except (subprocess.SubprocessError, json.JSONDecodeError) as e:
            print(f"❌ Error fetching build jobs: {e}", file=sys.stderr)
            return False, False

        matched: list[tuple[str, str, str]] = []
        for job in jobs:
            name = str(job.get("name") or job.get("label") or "")
            state = str(job.get("state") or "")
            jid = str(job.get("id") or "")
            if jid and _matches_job_pattern(name, job_pattern):
                matched.append((jid, name, state))

        if not matched:
            if fail_on_missing:
                print(
                    f"⚠️ No jobs found matching pattern '{job_pattern}' "
                    f"in build #{target.build_number}",
                    file=sys.stderr,
                )
            return False, not fail_on_missing

        all_ok = True
        for jid, name, state in matched:
            print(f"🚀 Retrying job '{name}' (ID: {jid}, status: {state})...")
            res = subprocess.run(["bk", "job", "retry", jid])
            if res.returncode != 0:
                all_ok = False
        return True, all_ok

    def handle_build(
        self,
        target: BuildkiteBuildTarget,
        mode: OperationMode,
        job_pattern: str = "",
        rebuild_if_no_failed_jobs: bool = True,
    ) -> bool:
        if mode == OperationMode.MATCH_JOBS:
            matched, all_ok = self.retry_jobs_by_name(
                target, job_pattern, fail_on_missing=True
            )
            return matched and all_ok

        if mode == OperationMode.UNBLOCK:
            jobs = self._view_build(target)
            unblocked, all_ok = self.unblock_manual_jobs(jobs)
            if not unblocked:
                print(
                    f"ℹ️ No blocked manual approval jobs found in build "
                    f"#{target.build_number}.",
                    file=sys.stderr,
                )
            return all_ok

        if mode == OperationMode.REBUILD:
            return self.rebuild_build(target)

        if mode == OperationMode.RETRY_FAILED:
            try:
                jobs = self._view_build(target)
            except (subprocess.SubprocessError, json.JSONDecodeError):
                if rebuild_if_no_failed_jobs:
                    return self.rebuild_build(target)
                return False

            unblocked_jobs, unblock_ok = self.unblock_manual_jobs(jobs)
            failed_jobs: list[dict[str, object]] = []
            for job in jobs:
                state = str(job.get("state") or "")
                if (
                    state in _FAILED_BK_JOB_STATES
                    and job.get("id")
                    and not job.get("retried_in_job_uuid")
                    and not job.get("retried_at")
                ):
                    failed_jobs.append(job)

            if failed_jobs:
                all_ok = unblock_ok
                for job in failed_jobs:
                    jid = str(job["id"])
                    jname = str(job.get("name") or job.get("label") or jid)
                    print(f"🚀 Retrying failed job '{jname}' (ID: {jid})...")
                    res = subprocess.run(["bk", "job", "retry", jid])
                    if res.returncode != 0:
                        all_ok = False
                return all_ok

            if unblocked_jobs:
                return unblock_ok

            if rebuild_if_no_failed_jobs:
                return unblock_ok and self.rebuild_build(target)
            return unblock_ok

        raise CiRetryError(f"Unsupported operation mode: {mode}")


class GitHubActionsProvider:
    """Executes GitHub Actions workflow and job reruns via the `gh` CLI."""

    def _ensure_cli(self) -> None:
        _check_cli("gh", "https://cli.github.com/")

    def _get_run_data(self, repo: str, run_id: str) -> dict[str, object]:
        cmd = [
            "gh",
            "run",
            "view",
            run_id,
            "--repo",
            repo,
            "--json",
            "status,conclusion,jobs",
        ]
        res = subprocess.run(cmd, capture_output=True, text=True, check=True)
        return _extract_json_object(res.stdout)

    def _wait_for_run_completion(
        self,
        repo: str,
        run_id: str,
        job_id: str = "",
    ) -> dict[str, object]:
        for attempt in range(_GH_MAX_POLL_ATTEMPTS):
            try:
                data = self._get_run_data(repo, run_id)
            except (subprocess.SubprocessError, json.JSONDecodeError) as e:
                print(
                    f"⚠️ Warning: Could not inspect GitHub Actions run {run_id}: {e}",
                    file=sys.stderr,
                )
                return {}

            status = str(data.get("status") or "").lower()
            raw_jobs = data.get("jobs", [])
            jobs = raw_jobs if isinstance(raw_jobs, list) else []

            if job_id:
                active_job_ids = {str(j.get("databaseId")) for j in jobs}
                if job_id not in active_job_ids:
                    # The job ID from an earlier attempt is no longer in the active
                    # jobs list, meaning a newer run_attempt is queued/running/done.
                    if (
                        status != "completed"
                        or str(data.get("conclusion") or "").lower() == "success"
                    ):
                        print(
                            f"ℹ️ GitHub Actions job {job_id} has already been "
                            f"superseded by a newer attempt in run {run_id} "
                            f"(status: {status})."
                        )
                        return data

            if status == "completed":
                return data

            print(
                f"⏳ GitHub Actions run {run_id} is currently '{status}' "
                f"(attempt {attempt + 1}/{_GH_MAX_POLL_ATTEMPTS}); waiting "
                f"{_GH_POLL_INTERVAL_SECONDS}s for run to complete before "
                f"rerunning..."
            )
            time.sleep(_GH_POLL_INTERVAL_SECONDS)

        print(
            f"⚠️ Timed out waiting for GitHub Actions run {run_id} to complete.",
            file=sys.stderr,
        )
        return {}

    def _rerun_failed_in_run(self, repo: str, run_id: str) -> bool:
        res = subprocess.run(["gh", "run", "rerun", run_id, "--failed", "--repo", repo])
        return res.returncode == 0

    def _rerun_job_with_fallback(
        self, repo: str, run_id: str, job_id: str
    ) -> tuple[bool, bool]:
        """Reruns a single job, falling back to `--failed` on the parent run.

        Returns:
            Tuple of `(succeeded, used_run_fallback)`.
        """
        res = subprocess.run(["gh", "run", "rerun", "--job", job_id, "--repo", repo])
        if res.returncode == 0:
            return True, False

        print(
            f"⚠️ Single-job rerun failed for {job_id} (exit {res.returncode}); "
            f"falling back to 'gh run rerun {run_id} --failed'..."
        )
        return self._rerun_failed_in_run(repo, run_id), True

    def handle_run(
        self,
        target: GitHubRunTarget,
        mode: OperationMode,
        job_pattern: str = "",
    ) -> bool:
        self._ensure_cli()
        if mode == OperationMode.UNBLOCK:
            return True

        data = self._wait_for_run_completion(
            target.repo, target.run_id, job_id=target.job_id
        )
        raw_jobs = data.get("jobs", [])
        jobs: list[dict[str, object]] = raw_jobs if isinstance(raw_jobs, list) else []

        if mode == OperationMode.REBUILD:
            print(
                f"🚀 Re-running entire GitHub Actions run {target.run_id} "
                f"({target.repo})..."
            )
            res = subprocess.run(
                ["gh", "run", "rerun", target.run_id, "--repo", target.repo]
            )
            return res.returncode == 0

        if mode == OperationMode.MATCH_JOBS:
            matched: list[tuple[str, str, str]] = []
            for job in jobs:
                name = str(job.get("name") or "")
                jid = str(job.get("databaseId") or "")
                conclusion = str(job.get("conclusion") or job.get("status") or "")
                if jid and _matches_job_pattern(name, job_pattern):
                    matched.append((jid, name, conclusion))

            if not matched:
                print(
                    f"⚠️ No GitHub Actions jobs found matching '{job_pattern}' "
                    f"in run {target.run_id}.",
                    file=sys.stderr,
                )
                return False

            for jid, name, conclusion in matched:
                print(
                    f"🚀 Retrying GitHub Actions job '{name}' "
                    f"(ID: {jid}, conclusion: {conclusion})..."
                )
                ok, used_fallback = self._rerun_job_with_fallback(
                    target.repo, target.run_id, jid
                )
                if used_fallback or not ok:
                    return ok
            return True

        if mode == OperationMode.RETRY_FAILED:
            if target.job_id:
                active_jobs_by_id = {str(j.get("databaseId")): j for j in jobs}
                if data and target.job_id not in active_jobs_by_id:
                    status = str(data.get("status") or "").lower()
                    conclusion = str(data.get("conclusion") or "").lower()
                    if status != "completed" or conclusion == "success":
                        return True

                target_job = active_jobs_by_id.get(target.job_id)
                if (
                    target_job
                    and str(target_job.get("conclusion") or "").lower() == "success"
                ):
                    print(
                        f"ℹ️ GitHub Actions job '{target_job.get('name')}' "
                        f"(ID: {target.job_id}) already succeeded."
                    )
                    return True

                print(
                    f"🚀 Retrying GitHub Actions job {target.job_id} in run "
                    f"{target.run_id} ({target.repo})..."
                )
                ok, _ = self._rerun_job_with_fallback(
                    target.repo, target.run_id, target.job_id
                )
                return ok

            if data and str(data.get("conclusion") or "").lower() == "success":
                print(f"ℹ️ GitHub Actions run {target.run_id} already succeeded.")
                return True

            print(
                f"🚀 Retrying failed jobs in GitHub Actions run {target.run_id} "
                f"({target.repo})..."
            )
            return self._rerun_failed_in_run(target.repo, target.run_id)

        raise CiRetryError(f"Unsupported operation mode: {mode}")

    def retry_job_by_id(
        self,
        target: GitHubJobTarget,
        mode: OperationMode = OperationMode.RETRY_FAILED,
        job_pattern: str = "",
    ) -> bool:
        self._ensure_cli()
        cmd = ["gh", "api", f"repos/{target.repo}/actions/jobs/{target.job_id}"]
        run_id = ""
        try:
            res = subprocess.run(cmd, capture_output=True, text=True, check=True)
            job_data = _extract_json_object(res.stdout)
            run_id = str(job_data.get("run_id") or "")
        except (subprocess.SubprocessError, json.JSONDecodeError) as e:
            print(
                f"⚠️ Could not resolve run_id for GitHub job {target.job_id} "
                f"via API: {e}",
                file=sys.stderr,
            )

        if run_id:
            return self.handle_run(
                GitHubRunTarget(
                    repo=target.repo,
                    run_id=run_id,
                    job_id=target.job_id,
                ),
                mode=mode,
                job_pattern=job_pattern,
            )

        print(f"🚀 Retrying GitHub Actions job ID: {target.job_id}...")
        res = subprocess.run(
            ["gh", "run", "rerun", "--job", target.job_id, "--repo", target.repo]
        )
        return res.returncode == 0


class PrOrchestrator:
    """Inspects PR checks and routes retries across Buildkite and GitHub Actions."""

    def __init__(
        self,
        buildkite: BuildkiteProvider,
        github_actions: GitHubActionsProvider,
    ) -> None:
        self._bk = buildkite
        self._gh = github_actions

    def _dispatch_github_runs(
        self,
        grouped_runs: Mapping[tuple[str, str], Sequence[str]],
        mode: OperationMode,
        job_pattern: str = "",
    ) -> bool:
        all_ok = True
        for (repo, run_id), job_ids in grouped_runs.items():
            single_job_id = job_ids[0] if len(job_ids) == 1 and job_ids[0] else ""
            run_mode = mode
            if mode == OperationMode.MATCH_JOBS and single_job_id:
                run_mode = OperationMode.RETRY_FAILED
            ok = self._gh.handle_run(
                GitHubRunTarget(
                    repo=repo,
                    run_id=run_id,
                    job_id=single_job_id if run_mode != OperationMode.REBUILD else "",
                ),
                mode=run_mode,
                job_pattern=job_pattern if run_mode == OperationMode.MATCH_JOBS else "",
            )
            if not ok:
                all_ok = False
        return all_ok

    def handle_pr(
        self,
        target: PrTarget,
        mode: OperationMode,
        job_pattern: str = "",
    ) -> bool:
        print(f"🔍 Inspecting PR #{target.pr_number} checks via gh...")
        checks = _get_pr_checks(target.pr_number)

        bk_checks: list[tuple[BuildkiteBuildTarget, bool]] = []
        gh_checks: list[tuple[str, GitHubRunTarget, bool]] = []
        for check in checks:
            link = str(check.get("link") or "")
            name = str(check.get("name") or "")
            is_failed = _is_check_failed(check)
            bk_target = _parse_buildkite_url(link)
            if bk_target:
                bk_checks.append((bk_target, is_failed))
            else:
                gh_target = _parse_github_actions_url(link)
                if gh_target:
                    gh_checks.append((name, gh_target, is_failed))

        if mode == OperationMode.UNBLOCK:
            if not bk_checks:
                print(
                    f"ℹ️ No Buildkite checks found for PR #{target.pr_number}.",
                    file=sys.stderr,
                )
                return True
            all_ok = True
            for bk_target, _ in bk_checks:
                if not self._bk.handle_build(bk_target, OperationMode.UNBLOCK):
                    all_ok = False
            return all_ok

        if mode == OperationMode.MATCH_JOBS:
            matched_any = False
            all_ok = True
            matched_gh_runs: dict[tuple[str, str], list[str]] = {}
            for cname, gh_target, _ in gh_checks:
                if _matches_job_pattern(cname, job_pattern):
                    matched_gh_runs.setdefault(
                        (gh_target.repo, gh_target.run_id), []
                    ).append(gh_target.job_id)

            if matched_gh_runs:
                matched_any = True
                if not self._dispatch_github_runs(
                    matched_gh_runs,
                    mode=OperationMode.MATCH_JOBS,
                    job_pattern=job_pattern,
                ):
                    all_ok = False

            for bk_target, _ in bk_checks:
                bk_matched, bk_ok = self._bk.retry_jobs_by_name(
                    bk_target, job_pattern, fail_on_missing=False
                )
                if bk_matched:
                    matched_any = True
                if not bk_ok:
                    all_ok = False

            if not matched_any:
                print(
                    f"⚠️ No GitHub Actions or Buildkite jobs found matching "
                    f"'{job_pattern}' for PR #{target.pr_number}.",
                    file=sys.stderr,
                )
                return False
            return all_ok

        if mode in (OperationMode.RETRY_FAILED, OperationMode.REBUILD):
            target_gh_runs: dict[tuple[str, str], list[str]] = {}
            for _, gh_target, is_failed in gh_checks:
                if is_failed or mode == OperationMode.REBUILD:
                    target_gh_runs.setdefault(
                        (gh_target.repo, gh_target.run_id), []
                    ).append(gh_target.job_id)

            all_ok = True
            gh_retried = bool(target_gh_runs)
            if target_gh_runs:
                if not self._dispatch_github_runs(target_gh_runs, mode=mode):
                    all_ok = False

            for bk_target, bk_failed in bk_checks:
                if not self._bk.handle_build(
                    bk_target,
                    mode=mode,
                    rebuild_if_no_failed_jobs=(bk_failed and not gh_retried),
                ):
                    all_ok = False

            if not bk_checks and not gh_retried:
                print(
                    f"ℹ️ No failing GitHub Actions or Buildkite checks found "
                    f"for PR #{target.pr_number}."
                )
            return all_ok

        raise CiRetryError(f"Unsupported operation mode: {mode}")


# ==============================================================================
# 5. Main
# ==============================================================================


def main(argv: Sequence[str]) -> int:
    args = _parse_args(argv)
    mode = _resolve_mode(args)

    try:
        target = _resolve_target(args)
        bk_provider = BuildkiteProvider()
        gh_provider = GitHubActionsProvider()

        if isinstance(target, BuildkiteJobTarget):
            ok = bk_provider.retry_job_by_uuid(target)
        elif isinstance(target, GitHubJobTarget):
            ok = gh_provider.retry_job_by_id(
                target, mode=mode, job_pattern=args.job_name
            )
        elif isinstance(target, GitHubRunTarget):
            ok = gh_provider.handle_run(target, mode=mode, job_pattern=args.job_name)
        elif isinstance(target, PrTarget):
            orchestrator = PrOrchestrator(bk_provider, gh_provider)
            ok = orchestrator.handle_pr(target, mode=mode, job_pattern=args.job_name)
        elif isinstance(target, BuildkiteBuildTarget):
            ok = bk_provider.handle_build(
                target,
                mode=mode,
                job_pattern=args.job_name,
                rebuild_if_no_failed_jobs=True,
            )
        else:
            raise CiRetryError(f"Unsupported target type: {target}")
    except CiRetryError as e:
        print(str(e), file=sys.stderr)
        return 1

    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
