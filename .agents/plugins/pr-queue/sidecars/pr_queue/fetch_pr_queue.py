#!/usr/bin/env python3
"""Fetches and filters pending GitHub pull requests using the `gh` CLI.

Usage:
  ./.agents/plugins/pr-queue/sidecars/pr_queue/fetch_pr_queue.py [options]

Options control repository scope, viewer identity, draft/approval/age filters,
GitHub search queries, and `--json` vs. Markdown output. Network calls use
bounded exponential-backoff retries for transient failures and run on demand
without background polling or automatic review execution.
"""

from __future__ import annotations

import argparse
import asyncio
import contextlib
import dataclasses
import datetime
import json
import logging
import random
import re
import sys
from collections.abc import Awaitable, Callable, Mapping, Sequence
from typing import TypeVar

# =============================================================================
# 1. Global Constants
# =============================================================================

DEFAULT_REPO = "bazel-contrib/rules_python"
# Hide untouched PRs after 30 days by default so stale backlog stays collapsible.
DEFAULT_MAX_AGE_DAYS = 30
# Match GitHub GraphQL connection `first` max (100) so PR and role lists align.
_DEFAULT_PR_LIMIT = 100
PR_JSON_FIELDS = (
    "number,title,url,author,createdAt,updatedAt,headRefName,headRefOid,"
    "baseRefName,isDraft,reviewDecision,reviewRequests,reviews,latestReviews,"
    "additions,deletions,changedFiles,labels,state,statusCheckRollup"
)

# Allow enough time for large PR lists over slower networks.
_GH_LIST_TIMEOUT_SECONDS = 30
# Identity lookups are tiny single-endpoint API calls.
_GH_USER_TIMEOUT_SECONDS = 15
# Cap at 3 attempts so transient GitHub 5xx blips recover within UI budgets.
_RETRY_MAX_ATTEMPTS = 3
# Start at 0.5s to give remote gateways brief recovery room before retry 2.
_RETRY_BASE_DELAY_SECONDS = 0.5
# Cap backoff at 1.0s (reached on attempt 2) to avoid multi-second UI stalls.
_RETRY_MAX_DELAY_SECONDS = 1.0
_SECONDS_PER_DAY = 86400
# Place unrecognized action buckets after all explicit queue priority buckets.
_DEFAULT_ACTION_PRIORITY = 99

_LOGGER = logging.getLogger("pr_queue.fetch")
_T = TypeVar("_T")
_SAFE_REPO_SEGMENT_RE = re.compile(r"\A[A-Za-z0-9._][A-Za-z0-9._-]*\Z")
_ANSI_ESCAPE_RE = re.compile(r"\x1b\[[0-9;]*[A-Za-z]|\x1b\][^\x07\x1b]*(?:\x07|\x1b\\)")
_CONTROL_CHARS_RE = re.compile(r"[\x00-\x1f\x7f-\x9f]+")

# LINT.IfChange(action_needed_buckets)
_ACTION_SORT_PRIORITY = {
    # keep-sorted start
    "approved": 4,
    "draft": 5,
    "my_pr": 3,
    "needs_review": 1,
    "review_requested": 0,
    "waiting_on_author": 2,
    # keep-sorted end
}
# LINT.ThenChange(//.agents/plugins/pr-queue/sidecars/pr_queue/index.html:action_needed_buckets)

_PROJECT_MEMBER_ASSOCIATIONS = frozenset(
    {
        # keep-sorted start
        "COLLABORATOR",
        "MEMBER",
        "OWNER",
        # keep-sorted end
    }
)

_TRANSIENT_ERROR_MARKERS = (
    # keep-sorted start
    "500",
    "502",
    "503",
    "504",
    "bad gateway",
    "connection refused",
    "connection reset",
    "connection timed out",
    "early eof",
    "eof",
    "gateway timeout",
    "internal server error",
    "rpc failed",
    "service unavailable",
    "temporary failure in name resolution",
    "the remote end hung up",
    "timed out",
    "tls handshake timeout",
    "unexpected eof",
    # keep-sorted end
)

_AUTH_ERROR_MARKERS = (
    # keep-sorted start
    "authentication",
    "bad credentials",
    "gh auth login",
    "http 401",
    "http 403",
    "not logged into any github hosts",
    "permission denied",
    # keep-sorted end
)

_GRAPHQL_PR_ASSOCIATIONS_QUERY = """
query($owner: String!, $name: String!, $limit: Int!) {
  repository(owner: $owner, name: $name) {
    pullRequests(
      states: OPEN,
      first: $limit,
      orderBy: {field: CREATED_AT, direction: DESC}
    ) {
      nodes {
        number
        authorAssociation
      }
    }
  }
}
""".strip()

_GRAPHQL_SEARCH_ASSOCIATIONS_QUERY = """
query($searchQuery: String!, $limit: Int!) {
  search(query: $searchQuery, type: ISSUE, first: $limit) {
    nodes {
      ... on PullRequest {
        number
        authorAssociation
      }
    }
  }
}
""".strip()


# =============================================================================
# 2. CLI Arguments
# =============================================================================


def parse_args(argv: Sequence[str] | None = None) -> argparse.Namespace:
    """Parses CLI arguments for the standalone PR queue fetcher."""
    parser = argparse.ArgumentParser(
        description="Fetch and filter open GitHub pull requests via `gh`."
    )
    parser.add_argument(
        "--repo",
        default=DEFAULT_REPO,
        help="GitHub repository in owner/name format (default: %(default)s)",
    )
    parser.add_argument(
        "--user",
        default="",
        help="GitHub username for review/author filters (defaults to `gh api user`)",
    )
    parser.add_argument(
        "--max-age-days",
        type=int,
        default=DEFAULT_MAX_AGE_DAYS,
        help=(
            "Mark PRs untouched longer than N days as stale; "
            "0 disables (default: %(default)s)"
        ),
    )
    parser.add_argument(
        "--review-requested-only",
        action="store_true",
        help="Show only PRs requesting review from --user",
    )
    parser.add_argument(
        "--include-approved",
        action="store_true",
        help="Include PRs already approved by --user",
    )
    parser.add_argument(
        "--include-authored",
        action="store_true",
        help="Include PRs authored by --user",
    )
    parser.add_argument(
        "--include-drafts",
        action="store_true",
        help="Include draft PRs",
    )
    parser.add_argument(
        "--search",
        default="",
        help="Additional GitHub search query passed to `gh pr list --search`",
    )
    parser.add_argument(
        "--limit",
        type=int,
        default=_DEFAULT_PR_LIMIT,
        help="Maximum open PRs to request from GitHub (default: %(default)s)",
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="Emit structured JSON instead of Markdown",
    )
    args = parser.parse_args(argv)
    if args.max_age_days < 0:
        parser.error("--max-age-days must be a non-negative integer.")
    if args.limit < 1:
        parser.error("--limit must be at least 1.")
    return args


# =============================================================================
# 3. Functions
# =============================================================================


def validate_repo_slug(repo: str, *, error_cls: type[Exception]) -> str:
    """Validates a GitHub `owner/name` repository slug and returns it stripped.

    Args:
      repo: Candidate `owner/name` repository identifier.
      error_cls: Exception class raised when validation fails.

    Returns:
      Normalized `owner/name` repository slug.
    """
    if any(ord(ch) < 32 or 127 <= ord(ch) <= 159 for ch in repo):
        raise error_cls("Repository slug must not contain control characters.")
    clean = repo.strip()
    owner, sep, name = clean.partition("/")
    if not sep or "/" in name:
        raise error_cls(f"Invalid repository format `{clean}`; expected `owner/name`.")
    for segment in (owner, name):
        if (
            segment in (".", "..")
            or ".." in segment
            or not _SAFE_REPO_SEGMENT_RE.match(segment)
        ):
            raise error_cls(
                f"Invalid repository format `{clean}`; expected `owner/name`."
            )
    return clean


def sanitize_log_text(value: object) -> str:
    """Strips ANSI escape sequences and C0/C1/DEL control chars from log text.

    Args:
      value: Untrusted value or exception to render safely on one log line.

    Returns:
      Cleaned single-line string safe for plain-text logs.
    """
    cleaned = _ANSI_ESCAPE_RE.sub("", str(value))
    return _CONTROL_CHARS_RE.sub(" ", cleaned).strip()


def validate_search_query(query: str, *, error_cls: type[Exception]) -> str:
    """Validates a GitHub search filter string against control chars and syntax breaks.

    Args:
      query: Candidate user search filter passed to `gh pr list` / GraphQL.
      error_cls: Exception class raised when validation fails.

    Returns:
      Stripped safe search query string.
    """
    if any(ord(ch) < 32 or 127 <= ord(ch) <= 159 for ch in query):
        raise error_cls("`custom_query` must not contain control characters.")
    clean = query.strip()
    in_quote = False
    escaped = False
    paren_depth = 0
    for ch in clean:
        if escaped:
            escaped = False
            continue
        if ch == "\\" and in_quote:
            escaped = True
            continue
        if ch == '"':
            in_quote = not in_quote
        elif not in_quote:
            if ch == "(":
                paren_depth += 1
            elif ch == ")":
                paren_depth -= 1
                if paren_depth < 0:
                    raise error_cls("`custom_query` has unbalanced parentheses.")
    if in_quote:
        raise error_cls("`custom_query` has an unclosed quote.")
    if paren_depth != 0:
        raise error_cls("`custom_query` has unbalanced parentheses.")
    return clean


def format_subprocess_error(
    command_label: str,
    returncode: int,
    stdout: str,
    stderr: str,
) -> str:
    """Formats subprocess failure details with demarcated STDOUT/STDERR blocks."""
    lines = [f"`{command_label}` failed (exit {returncode})."]
    clean_out = stdout.strip()
    clean_err = stderr.strip()
    if clean_out:
        lines.extend(
            [
                "==================== STDOUT BEGIN ====================",
                clean_out,
                "==================== STDOUT END ====================",
            ]
        )
    if clean_err:
        lines.extend(
            [
                "==================== STDERR BEGIN ====================",
                clean_err,
                "==================== STDERR END ====================",
            ]
        )
    return "\n".join(lines)


async def run_subprocess_async(
    cmd: Sequence[str],
    *,
    label: str,
    timeout_seconds: int,
    error_cls: type[Exception],
    missing_binary_message: str,
) -> tuple[int, str, str]:
    """Runs a subprocess under asyncio and returns `(returncode, stdout, stderr)`.

    Args:
      cmd: Full executable and argument vector.
      label: Human-readable command label for timeout errors.
      timeout_seconds: Maximum wall-clock runtime before killing the process.
      error_cls: Exception class raised on missing binary or timeout.
      missing_binary_message: Error text used when executable is not found.

    Returns:
      Tuple `(returncode, stdout, stderr)` decoded as UTF-8.
    """
    try:
        proc = await asyncio.create_subprocess_exec(
            *cmd,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
        )
    except FileNotFoundError as exc:
        raise error_cls(missing_binary_message) from exc

    try:
        stdout_b, stderr_b = await asyncio.wait_for(
            proc.communicate(), timeout=timeout_seconds
        )
    except TimeoutError as exc:
        with contextlib.suppress(OSError):
            proc.kill()
            await proc.wait()
        raise error_cls(f"`{label}` timed out after {timeout_seconds}s") from exc

    stdout = stdout_b.decode("utf-8", errors="replace") if stdout_b else ""
    stderr = stderr_b.decode("utf-8", errors="replace") if stderr_b else ""
    assert proc.returncode is not None  # type assert
    return (proc.returncode, stdout, stderr)


def is_transient_error(detail: str) -> bool:
    """Reports whether error text indicates a retryable network or 5xx error."""
    lowered = detail.lower()
    if any(marker in lowered for marker in _AUTH_ERROR_MARKERS):
        return False
    return any(marker in lowered for marker in _TRANSIENT_ERROR_MARKERS)


def _retry_delay_seconds(attempt_index: int) -> float:
    base = min(
        _RETRY_MAX_DELAY_SECONDS,
        _RETRY_BASE_DELAY_SECONDS * (2**attempt_index),
    )
    # Add ±15% symmetric jitter to avoid synchronized retry bursts.
    return base * random.uniform(0.85, 1.15)


async def retry_async(
    operation: Callable[[], Awaitable[_T]],
    *,
    is_retryable: Callable[[Exception], bool],
    label: str,
) -> _T:
    """Retries an async operation on transient errors with exponential backoff."""
    for attempt in range(_RETRY_MAX_ATTEMPTS - 1):
        try:
            return await operation()
        except Exception as exc:
            if not is_retryable(exc):
                raise
            delay = _retry_delay_seconds(attempt)
            _LOGGER.warning(
                "%s attempt %d/%d failed (%s); retrying in %.2fs",
                sanitize_log_text(label),
                attempt + 1,
                _RETRY_MAX_ATTEMPTS,
                sanitize_log_text(exc),
                delay,
            )
            await asyncio.sleep(delay)
    return await operation()


def _build_gh_error(
    label: str, returncode: int, stdout: str, stderr: str
) -> FetchError:
    combined = f"{stderr}\n{stdout}".lower()
    hint = ""
    if any(marker in combined for marker in _AUTH_ERROR_MARKERS):
        hint = f"GitHub authentication failed for `{label}`; run `gh auth login`. "
    elif "rate limit" in combined:
        hint = f"GitHub API rate limit exceeded during `{label}`. "
    detail = format_subprocess_error(label, returncode, stdout, stderr)
    return FetchError(f"{hint}{detail}")


def parse_iso_timestamp(value: str) -> datetime.datetime:
    """Parses a GitHub ISO 8601 timestamp string into a UTC-aware datetime."""
    parsed = datetime.datetime.fromisoformat(value.strip())
    if parsed.tzinfo is None:
        return parsed.replace(tzinfo=datetime.UTC)
    return parsed.astimezone(datetime.UTC)


def compute_age_days(timestamp: str, now: datetime.datetime) -> int:
    """Returns whole non-negative days elapsed since timestamp."""
    if not timestamp:
        return 0
    try:
        parsed = parse_iso_timestamp(timestamp)
    except ValueError:
        return 0
    delta_seconds = max(0.0, (now - parsed).total_seconds())
    return int(delta_seconds // _SECONDS_PER_DAY)


async def _run_gh_once_async(args: Sequence[str], timeout_seconds: int) -> str:
    label = f"gh {' '.join(args[:3])}"
    returncode, stdout, stderr = await run_subprocess_async(
        ["gh", *args],
        label=label,
        timeout_seconds=timeout_seconds,
        error_cls=FetchError,
        missing_binary_message=(
            "`gh` CLI executable was not found on PATH; install GitHub CLI."
        ),
    )
    if returncode != 0:
        raise _build_gh_error(label, returncode, stdout, stderr)
    return stdout


async def run_gh_command_async(args: Sequence[str], timeout_seconds: int) -> str:
    """Runs a `gh` subprocess under asyncio with bounded transient retries."""
    label = f"gh {' '.join(args[:3])}"
    return await retry_async(
        lambda: _run_gh_once_async(args, timeout_seconds),
        is_retryable=lambda exc: (
            isinstance(exc, FetchError) and is_transient_error(str(exc))
        ),
        label=label,
    )


def _parse_gh_login(output: str) -> str:
    login = output.strip()
    if not login:
        raise FetchError(
            "Unable to determine GitHub user via `gh api user`; run `gh auth login`."
        )
    return login


async def _default_gh_runner(args: Sequence[str], timeout_seconds: int) -> str:
    return await run_gh_command_async(args, timeout_seconds)


async def get_current_gh_user_async(
    runner: Callable[[Sequence[str], int], Awaitable[str]] = _default_gh_runner,
) -> str:
    """Fetches the authenticated GitHub login from `gh api user`.

    Args:
      runner: Async `gh` command runner callable.

    Returns:
      Authenticated GitHub username.
    """
    output = await runner(["api", "user", "--jq", ".login"], _GH_USER_TIMEOUT_SECONDS)
    return _parse_gh_login(output)


def _extract_reviewer_name(item: Mapping[str, object]) -> str:
    # `gh` returns either direct fields or a nested `requestedReviewer` object.
    nested = item.get("requestedReviewer")
    containers: tuple[Mapping[str, object], ...] = (
        (item, nested) if isinstance(nested, dict) else (item,)
    )
    for container in containers:
        for key in ("login", "slug", "name"):
            candidate = container.get(key)
            if candidate:
                return str(candidate)
    return ""


def _extract_reviewer_names(raw_requests: object) -> list[str]:
    names: list[str] = []
    if not isinstance(raw_requests, list):
        return names
    for item in raw_requests:
        if not isinstance(item, dict):
            continue
        name = _extract_reviewer_name(item)
        if name and name not in names:
            names.append(name)
    return names


def _extract_review_states(raw_pr: Mapping[str, object]) -> dict[str, str]:
    """Maps reviewer login (preserving case from data) to latest review state."""
    latest = raw_pr.get("latestReviews")
    entries = latest if isinstance(latest, list) and latest else raw_pr.get("reviews")
    states: dict[str, str] = {}
    if not isinstance(entries, list):
        return states
    for review in entries:
        if not isinstance(review, dict):
            continue
        author_obj = review.get("author")
        if not isinstance(author_obj, dict):
            continue
        login = str(author_obj.get("login") or "").strip()
        state = str(review.get("state") or "").strip().upper()
        if login and state:
            states[login] = state
    return states


def _summarize_checks(raw_rollup: object) -> tuple[str, int, int, int, int]:
    """Summarizes statusCheckRollup entries into aggregate CI counts.

    Args:
      raw_rollup: Raw `statusCheckRollup` value decoded from `gh pr list` JSON.

    Returns:
      Tuple `(state, passed, failed, pending, total)`.
    """
    if not isinstance(raw_rollup, list) or not raw_rollup:
        return ("none", 0, 0, 0, 0)

    passed = 0
    failed = 0
    pending = 0
    cancelled = 0
    total = 0

    for item in raw_rollup:
        if not isinstance(item, dict):
            continue
        total += 1
        typename = str(item.get("__typename") or "")
        # Legacy StatusContext items carry `state` while CheckRun items carry `status`/`conclusion`.
        if typename == "StatusContext" or (
            "state" in item and "conclusion" not in item
        ):
            state = str(item.get("state") or "").upper()
            if state == "SUCCESS":
                passed += 1
            elif state in ("FAILURE", "ERROR"):
                failed += 1
            elif state in ("PENDING", "EXPECTED"):
                pending += 1
            continue

        status = str(item.get("status") or "").upper()
        conclusion = str(item.get("conclusion") or "").upper()
        if status and status != "COMPLETED":
            pending += 1
        elif conclusion in ("SUCCESS", "NEUTRAL", "SKIPPED"):
            passed += 1
        elif conclusion == "CANCELLED":
            cancelled += 1
        elif conclusion in (
            "FAILURE",
            "TIMED_OUT",
            "ACTION_REQUIRED",
            "STARTUP_FAILURE",
            "STALE",
        ):
            failed += 1
        elif not conclusion:
            pending += 1

    # LINT.IfChange(checks_state_values)
    if failed > 0:
        overall = "failing"
    elif pending > 0:
        overall = "pending"
    elif cancelled > 0 and passed == 0:
        overall = "cancelled"
    elif passed > 0 or cancelled > 0:
        overall = "passing"
    else:
        overall = "none"
    # LINT.ThenChange(//.agents/plugins/pr-queue/sidecars/pr_queue/index.html:checks_state_values)
    return (overall, passed, failed, pending, total)


def _determine_action_needed(
    *,
    is_draft: bool,
    is_my_pr: bool,
    review_requested_from_me: bool,
    my_review_state: str,
    review_decision: str,
    changes_requested_by: Sequence[str],
) -> str:
    if is_draft:
        return "draft"
    if review_requested_from_me:
        return "review_requested"
    if is_my_pr:
        return "my_pr"
    if my_review_state == "APPROVED" or review_decision == "APPROVED":
        return "approved"
    if review_decision == "CHANGES_REQUESTED" or bool(changes_requested_by):
        return "waiting_on_author"
    return "needs_review"


def _extract_author_info(raw_pr: Mapping[str, object]) -> tuple[str, bool]:
    author_obj = raw_pr.get("author")
    author_dict = author_obj if isinstance(author_obj, dict) else {}
    author_login = str(author_dict.get("login") or "ghost")
    is_bot = (
        bool(author_dict.get("is_bot"))
        or author_login.endswith("[bot]")
        or author_login.startswith("app/")
    )
    return (author_login, is_bot)


def _extract_labels(raw_pr: Mapping[str, object]) -> tuple[str, ...]:
    labels_raw = raw_pr.get("labels")
    if not isinstance(labels_raw, list):
        return ()
    return tuple(
        str(label["name"])
        for label in labels_raw
        if isinstance(label, dict) and label.get("name")
    )


def _find_viewer_review_state(
    viewer_lower: str, review_states: Mapping[str, str]
) -> str:
    if not viewer_lower:
        return ""
    for login, state in review_states.items():
        if login.lower() == viewer_lower:
            return state
    return ""


def _int_field(raw_pr: Mapping[str, object], key: str) -> int:
    val = raw_pr.get(key)
    if isinstance(val, int) and not isinstance(val, bool):
        return val
    return 0


def normalize_pr(
    raw_pr: Mapping[str, object],
    *,
    repo: str,
    viewer: str,
    max_age_days: int,
    now: datetime.datetime,
    author_association: str = "",
) -> PrSummary:
    """Converts a single `gh pr list` or `gh pr view` JSON item into a PrSummary.

    Args:
      raw_pr: Parsed JSON object for one PR from `gh pr list` or `gh pr view`.
      repo: Repository slug in `owner/name` form.
      viewer: Active GitHub login for viewer-scoped fields.
      max_age_days: Days since last update after which PRs are marked stale.
      now: Reference UTC timestamp used to compute age fields.
      author_association: Optional GraphQL `authorAssociation` override.

    Returns:
      Normalized immutable PrSummary instance.
    """
    author_login, is_bot = _extract_author_info(raw_pr)
    clean_assoc = (
        (author_association or str(raw_pr.get("authorAssociation") or ""))
        .strip()
        .upper()
    )
    is_project_member = (not is_bot) and (clean_assoc in _PROJECT_MEMBER_ASSOCIATIONS)

    created_at = str(raw_pr.get("createdAt") or "")
    updated_at = str(raw_pr.get("updatedAt") or created_at)
    age_days = compute_age_days(created_at, now)
    days_since_update = compute_age_days(updated_at, now)
    is_stale = max_age_days > 0 and days_since_update > max_age_days

    requested = _extract_reviewer_names(raw_pr.get("reviewRequests"))
    viewer_lower = viewer.lower()
    review_requested_from_me = bool(
        viewer_lower and any(name.lower() == viewer_lower for name in requested)
    )

    review_states = _extract_review_states(raw_pr)
    approved_by = tuple(
        sorted(login for login, state in review_states.items() if state == "APPROVED")
    )
    changes_requested_by = tuple(
        sorted(
            login
            for login, state in review_states.items()
            if state == "CHANGES_REQUESTED"
        )
    )
    my_review_state = _find_viewer_review_state(viewer_lower, review_states)
    labels = _extract_labels(raw_pr)

    checks_state, checks_passed, checks_failed, checks_pending, checks_total = (
        _summarize_checks(raw_pr.get("statusCheckRollup"))
    )

    is_draft = bool(raw_pr.get("isDraft"))
    pr_state = str(raw_pr.get("state") or "OPEN").strip().upper() or "OPEN"
    review_decision = str(raw_pr.get("reviewDecision") or "").upper() or "NONE"
    is_my_pr = bool(viewer_lower and author_login.lower() == viewer_lower)

    action_needed = _determine_action_needed(
        is_draft=is_draft,
        is_my_pr=is_my_pr,
        review_requested_from_me=review_requested_from_me,
        my_review_state=my_review_state,
        review_decision=review_decision,
        changes_requested_by=changes_requested_by,
    )

    return PrSummary(
        repo=repo,
        number=_int_field(raw_pr, "number"),
        title=str(raw_pr.get("title") or ""),
        url=str(raw_pr.get("url") or ""),
        author=author_login,
        author_association=clean_assoc,
        is_project_member=is_project_member,
        is_bot=is_bot,
        created_at=created_at,
        updated_at=updated_at,
        age_days=age_days,
        days_since_update=days_since_update,
        head_ref_name=str(raw_pr.get("headRefName") or ""),
        head_ref_oid=str(raw_pr.get("headRefOid") or ""),
        base_ref_name=str(raw_pr.get("baseRefName") or ""),
        is_draft=is_draft,
        review_decision=review_decision,
        review_requested_from_me=review_requested_from_me,
        requested_reviewers=tuple(requested),
        my_review_state=my_review_state,
        approved_by=approved_by,
        changes_requested_by=changes_requested_by,
        additions=_int_field(raw_pr, "additions"),
        deletions=_int_field(raw_pr, "deletions"),
        changed_files=_int_field(raw_pr, "changedFiles"),
        labels=labels,
        checks_state=checks_state,
        checks_passed=checks_passed,
        checks_failed=checks_failed,
        checks_pending=checks_pending,
        checks_total=checks_total,
        action_needed=action_needed,
        is_stale=is_stale,
        state=pr_state,
    )


def _updated_epoch(timestamp: str) -> float:
    if not timestamp:
        return 0.0
    try:
        return parse_iso_timestamp(timestamp).timestamp()
    except ValueError:
        return 0.0


def sort_prs(prs: Sequence[PrSummary]) -> list[PrSummary]:
    """Sorts PRs by queue priority first, then most recently updated descending."""
    return sorted(
        prs,
        key=lambda pr: (
            _ACTION_SORT_PRIORITY.get(pr.action_needed, _DEFAULT_ACTION_PRIORITY),
            -_updated_epoch(pr.updated_at),
            -pr.number,
        ),
    )


def _build_pr_list_args(repo: str, clean_query: str, limit: int) -> list[str]:
    args = [
        "pr",
        "list",
        f"--repo={repo}",
        "--state",
        "open",
        "--limit",
        str(max(1, limit)),
        "--json",
        PR_JSON_FIELDS,
    ]
    if clean_query:
        args.append(f"--search={clean_query}")
    return args


def _build_author_association_args(
    repo: str, clean_query: str, limit: int
) -> list[str] | None:
    owner, sep, name = repo.partition("/")
    if not sep or not owner or not name:
        return None
    # GitHub GraphQL connections cap `first` at 100 items per page.
    gql_limit = min(100, max(1, limit))
    if clean_query:
        search_expr = f"repo:{repo} is:pr is:open {clean_query}"
        return [
            "api",
            "graphql",
            "--raw-field",
            f"query={_GRAPHQL_SEARCH_ASSOCIATIONS_QUERY}",
            "--raw-field",
            f"searchQuery={search_expr}",
            "--field",
            f"limit={gql_limit}",
        ]
    return [
        "api",
        "graphql",
        "--raw-field",
        f"query={_GRAPHQL_PR_ASSOCIATIONS_QUERY}",
        "--raw-field",
        f"owner={owner}",
        "--raw-field",
        f"name={name}",
        "--field",
        f"limit={gql_limit}",
    ]


def _extract_association_nodes(data: Mapping[str, object]) -> object:
    repo_obj = data.get("repository")
    if isinstance(repo_obj, dict):
        prs_obj = repo_obj.get("pullRequests")
        if isinstance(prs_obj, dict):
            return prs_obj.get("nodes")
    search_obj = data.get("search")
    if isinstance(search_obj, dict):
        return search_obj.get("nodes")
    return None


def _parse_author_associations(raw_output: str) -> dict[int, str]:
    try:
        parsed = json.loads(raw_output or "{}")
    except json.JSONDecodeError:
        return {}
    if not isinstance(parsed, dict):
        return {}
    data = parsed.get("data")
    if not isinstance(data, dict):
        return {}

    nodes = _extract_association_nodes(data)
    if not isinstance(nodes, list):
        return {}

    associations: dict[int, str] = {}
    for node in nodes:
        if not isinstance(node, dict) or "number" not in node:
            continue
        assoc = str(node.get("authorAssociation") or "").strip().upper()
        if assoc:
            with contextlib.suppress(TypeError, ValueError):
                associations[int(node["number"])] = assoc
    return associations


def _parse_and_filter_prs(
    raw_output: str,
    *,
    clean_repo: str,
    viewer: str,
    max_age_days: int,
    review_requested_only: bool,
    exclude_approved_by_me: bool,
    exclude_authored_by_me: bool,
    exclude_drafts: bool,
    now: datetime.datetime | None,
    author_associations: Mapping[int, str],
) -> PrQueueResult:
    """Parses `gh pr list` JSON, normalizes each PR, and partitions active/stale.

    Args:
      raw_output: Raw JSON string from `gh pr list --json`.
      clean_repo: Validated repository slug (`owner/name`).
      viewer: Active GitHub login used for personalized filters.
      max_age_days: Days since update after which PRs move to stale_prs.
      review_requested_only: Retain only PRs requesting review from viewer.
      exclude_approved_by_me: Omit PRs whose latest viewer review is APPROVED.
      exclude_authored_by_me: Omit PRs authored by viewer.
      exclude_drafts: Omit draft PRs.
      now: Optional UTC timestamp override for age calculations.
      author_associations: Map of PR number to GraphQL authorAssociation value.

    Returns:
      Sorted and partitioned PrQueueResult.
    """
    try:
        raw_items = json.loads(raw_output or "[]")
    except json.JSONDecodeError as exc:
        raise FetchError(f"Invalid JSON from `gh pr list`: {exc}") from exc
    if not isinstance(raw_items, list):
        raise FetchError("Expected JSON list from `gh pr list`.")

    current_time = now or datetime.datetime.now(datetime.UTC)
    viewer_lower = viewer.lower()

    active_prs: list[PrSummary] = []
    stale_prs: list[PrSummary] = []
    skipped_drafts = 0
    skipped_authored = 0
    skipped_approved = 0

    for item in raw_items:
        if not isinstance(item, dict) or "number" not in item:
            continue
        pr_num = int(item["number"])
        summary = normalize_pr(
            item,
            repo=clean_repo,
            viewer=viewer,
            max_age_days=max(0, max_age_days),
            now=current_time,
            author_association=author_associations.get(pr_num, ""),
        )
        if exclude_drafts and summary.is_draft:
            skipped_drafts += 1
            continue
        if (
            exclude_authored_by_me
            and viewer_lower
            and summary.author.lower() == viewer_lower
        ):
            skipped_authored += 1
            continue
        if exclude_approved_by_me and summary.my_review_state == "APPROVED":
            skipped_approved += 1
            continue
        if review_requested_only and not summary.review_requested_from_me:
            continue

        if summary.is_stale:
            stale_prs.append(summary)
        else:
            active_prs.append(summary)

    return PrQueueResult(
        repo=clean_repo,
        viewer=viewer,
        prs=sort_prs(active_prs),
        stale_prs=sort_prs(stale_prs),
        skipped_drafts=skipped_drafts,
        skipped_authored=skipped_authored,
        skipped_approved=skipped_approved,
        max_age_days=max(0, max_age_days),
    )


async def _ready_value(value: str) -> str:
    return value


async def fetch_pr_queue_async(
    *,
    repo: str = DEFAULT_REPO,
    user: str = "",
    max_age_days: int = DEFAULT_MAX_AGE_DAYS,
    review_requested_only: bool = False,
    exclude_approved_by_me: bool = True,
    exclude_authored_by_me: bool = True,
    exclude_drafts: bool = True,
    custom_query: str = "",
    limit: int = _DEFAULT_PR_LIMIT,
    runner: Callable[[Sequence[str], int], Awaitable[str]] = _default_gh_runner,
    now: datetime.datetime | None = None,
) -> PrQueueResult:
    """Queries GitHub open PRs with asyncio and applies queue filters.

    Args:
      repo: Target repository slug (`owner/name`).
      user: Viewer GitHub login override; empty resolves via `gh api user`.
      max_age_days: Stale threshold in days; 0 disables stale partitioning.
      review_requested_only: Retain only PRs requesting review from viewer.
      exclude_approved_by_me: Omit PRs whose latest review by viewer is APPROVED.
      exclude_authored_by_me: Omit PRs authored by viewer.
      exclude_drafts: Omit draft PRs.
      custom_query: Optional GitHub search filter string.
      limit: Maximum number of open PRs to fetch.
      runner: Async `gh` command runner callable.
      now: Reference UTC timestamp for deterministic age calculation.

    Returns:
      Filtered and sorted PrQueueResult.
    """
    clean_repo = validate_repo_slug(repo, error_cls=FetchError)
    clean_query = validate_search_query(custom_query, error_cls=FetchError)
    viewer = user.strip()

    args = _build_pr_list_args(clean_repo, clean_query, limit)
    assoc_args = _build_author_association_args(clean_repo, clean_query, limit)

    list_coro = runner(args, _GH_LIST_TIMEOUT_SECONDS)
    assoc_coro = (
        runner(assoc_args, _GH_LIST_TIMEOUT_SECONDS)
        if assoc_args is not None
        else _ready_value("{}")
    )
    user_coro = (
        get_current_gh_user_async(runner=runner) if not viewer else _ready_value(viewer)
    )

    raw_output, assoc_res, viewer_res = await asyncio.gather(
        list_coro, assoc_coro, user_coro, return_exceptions=True
    )
    if isinstance(viewer_res, BaseException):
        raise viewer_res
    if isinstance(raw_output, BaseException):
        raise raw_output
    if isinstance(assoc_res, FetchError):
        # GraphQL membership metadata is advisory; degrade safely if secondary lookup fails.
        _LOGGER.warning(
            "GraphQL authorAssociation lookup failed: %s",
            sanitize_log_text(assoc_res),
        )
        associations: dict[int, str] = {}
    elif isinstance(assoc_res, BaseException):
        raise assoc_res
    else:
        associations = _parse_author_associations(assoc_res)

    return _parse_and_filter_prs(
        raw_output,
        clean_repo=clean_repo,
        viewer=viewer_res,
        max_age_days=max_age_days,
        review_requested_only=review_requested_only,
        exclude_approved_by_me=exclude_approved_by_me,
        exclude_authored_by_me=exclude_authored_by_me,
        exclude_drafts=exclude_drafts,
        now=now,
        author_associations=associations,
    )


def format_markdown(result: PrQueueResult) -> str:
    """Formats a PrQueueResult as concise Markdown for terminal inspection."""
    lines = [
        f"# PR Queue: {result.repo} (viewer: {result.viewer})",
        "",
        (
            f"Active: {len(result.prs)} | Stale (>{result.max_age_days}d): "
            f"{len(result.stale_prs)} | Skipped drafts: {result.skipped_drafts}"
        ),
        "",
    ]
    if not result.prs:
        lines.append("No matching open pull requests.")
    for pr in result.prs:
        req_tag = " [review-requested]" if pr.review_requested_from_me else ""
        member_tag = " [member]" if pr.is_project_member else ""
        checks_tag = f"checks={pr.checks_state}"
        lines.append(
            f"- **#{pr.number}** [{pr.action_needed}{req_tag}] "
            f"{pr.title} (@{pr.author}{member_tag}, "
            f"{pr.days_since_update}d since update, "
            f"{checks_tag}) — {pr.url}"
        )
    if result.stale_prs:
        lines.extend(["", f"## Stale (>{result.max_age_days} days since update)", ""])
        for pr in result.stale_prs:
            member_tag = " [member]" if pr.is_project_member else ""
            lines.append(
                f"- **#{pr.number}** {pr.title} (@{pr.author}{member_tag}, "
                f"{pr.days_since_update}d) — {pr.url}"
            )
    return "\n".join(lines) + "\n"


# =============================================================================
# 4. Classes
# =============================================================================


class FetchError(Exception):
    """Raised when querying GitHub pull requests fails."""


@dataclasses.dataclass(frozen=True)
class PrSummary:
    """Normalized summary of a GitHub pull request."""

    # GitHub repository in owner/name format.
    repo: str
    # Pull request number.
    number: int
    # Pull request title.
    title: str
    # Web URL to the pull request.
    url: str
    # GitHub login of the PR author.
    author: str
    # Author repository association (OWNER, MEMBER, COLLABORATOR, etc.).
    author_association: str
    # Whether the author is a project owner, org member, or repo collaborator.
    is_project_member: bool
    # Whether the author login represents an automated bot account.
    is_bot: bool
    # ISO 8601 creation timestamp string from GitHub.
    created_at: str
    # ISO 8601 last-updated timestamp string from GitHub.
    updated_at: str
    # Whole days elapsed since created_at.
    age_days: int
    # Whole days elapsed since updated_at.
    days_since_update: int
    # Source branch name of the PR.
    head_ref_name: str
    # Head commit SHA of the PR.
    head_ref_oid: str
    # Target base branch name of the PR.
    base_ref_name: str
    # Whether the PR is currently marked as draft.
    is_draft: bool
    # Aggregate GitHub review decision (APPROVED, CHANGES_REQUESTED, etc.).
    review_decision: str
    # Whether the configured viewer is explicitly requested for review.
    review_requested_from_me: bool
    # Logins or team slugs listed in pending review requests.
    requested_reviewers: tuple[str, ...]
    # Viewer's latest review state (APPROVED, CHANGES_REQUESTED, etc.) or "".
    my_review_state: str
    # Logins whose latest review state is APPROVED.
    approved_by: tuple[str, ...]
    # Logins whose latest review state is CHANGES_REQUESTED.
    changes_requested_by: tuple[str, ...]
    # Added line count across the PR diff.
    additions: int
    # Deleted line count across the PR diff.
    deletions: int
    # Number of changed files in the PR diff.
    changed_files: int
    # Label names attached to the PR.
    labels: tuple[str, ...]
    # Aggregate CI check state: passing, failing, pending, cancelled, or none.
    checks_state: str
    # Count of passing CI checks.
    checks_passed: int
    # Count of failing or errored CI checks.
    checks_failed: int
    # Count of queued or in-progress CI checks.
    checks_pending: int
    # Total number of CI check entries in statusCheckRollup.
    checks_total: int
    # Derived queue bucket: review_requested, needs_review, waiting_on_author, etc.
    action_needed: str
    # Whether the PR exceeds max_age_days since updated_at.
    is_stale: bool
    # PR lifecycle state from GitHub (OPEN, CLOSED, or MERGED).
    state: str = "OPEN"

    def to_dict(self) -> dict[str, object]:
        """Serializes this summary into a JSON-compatible dict."""
        data: dict[str, object] = dataclasses.asdict(self)
        tuple_fields = (
            "requested_reviewers",
            "approved_by",
            "changes_requested_by",
            "labels",
        )
        for key in tuple_fields:
            raw_val = data[key]
            if isinstance(raw_val, (list, tuple)):
                data[key] = list(raw_val)
        return data


@dataclasses.dataclass(frozen=True)
class PrQueueResult:
    """Filtered pull request queue response returned by fetch_pr_queue_async."""

    # GitHub repository queried in owner/name format.
    repo: str
    # Resolved GitHub login used for personalized filters, or "".
    viewer: str
    # Active open PRs matching all configured filters.
    prs: list[PrSummary]
    # Open PRs matching filters except exceeding max_age_days since update.
    stale_prs: list[PrSummary]
    # Count of open PRs skipped solely because isDraft was true.
    skipped_drafts: int
    # Count of open PRs skipped solely because viewer authored them.
    skipped_authored: int
    # Count of open PRs skipped solely because viewer already approved them.
    skipped_approved: int
    # Effective max_age_days cutoff applied during partitioning.
    max_age_days: int

    def to_dict(self) -> dict[str, object]:
        """Serializes the queue result into a JSON-compatible dict."""
        return {
            "repo": self.repo,
            "viewer": self.viewer,
            "count": len(self.prs),
            "stale_count": len(self.stale_prs),
            "skipped_drafts": self.skipped_drafts,
            "skipped_authored": self.skipped_authored,
            "skipped_approved": self.skipped_approved,
            "max_age_days": self.max_age_days,
            "prs": [pr.to_dict() for pr in self.prs],
            "stale_prs": [pr.to_dict() for pr in self.stale_prs],
        }


# =============================================================================
# 5. Main
# =============================================================================


async def async_main(argv: Sequence[str] | None = None) -> int:
    """Runs the PR queue fetcher CLI inside an asyncio event loop."""
    args = parse_args(argv)
    try:
        result = await fetch_pr_queue_async(
            repo=args.repo,
            user=args.user,
            max_age_days=args.max_age_days,
            review_requested_only=args.review_requested_only,
            exclude_approved_by_me=not args.include_approved,
            exclude_authored_by_me=not args.include_authored,
            exclude_drafts=not args.include_drafts,
            custom_query=args.search,
            limit=args.limit,
        )
    except FetchError as exc:
        print(f"Error: {exc}", file=sys.stderr)
        return 1

    if args.json:
        print(json.dumps(result.to_dict(), indent=2))
    else:
        print(format_markdown(result), end="")
    return 0


def main(argv: Sequence[str] | None = None) -> int:
    """CLI entry point returning process exit code."""
    return asyncio.run(async_main(argv))


if __name__ == "__main__":
    raise SystemExit(main())
