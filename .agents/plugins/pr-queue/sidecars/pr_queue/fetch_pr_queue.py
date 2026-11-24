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
import heapq
import json
import logging
import random
import re
import sys
from collections import deque
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
# Omit `reviews` and `statusCheckRollup` from bulk `gh pr list` so 100-PR
# GraphQL queries avoid 100x100 nested node fan-out and GitHub 502/504 timeouts.
_PR_LIST_JSON_FIELDS = (
    "number,title,url,body,author,createdAt,updatedAt,headRefName,headRefOid,"
    "baseRefName,isCrossRepository,isDraft,reviewDecision,reviewRequests,"
    "latestReviews,additions,deletions,changedFiles,labels,state"
)
PR_JSON_FIELDS = f"{_PR_LIST_JSON_FIELDS},statusCheckRollup"

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
_ACTION_BUCKET_LABELS = {
    # keep-sorted start
    "approved": "Approved",
    "draft": "Draft",
    "my_pr": "Your PR",
    "needs_review": "Needs Review",
    "review_requested": "Review Requested",
    "waiting_on_author": "Changes Requested",
    # keep-sorted end
}
_ORDERED_ACTION_LABELS = " -> ".join(
    _ACTION_BUCKET_LABELS[key]
    for key in sorted(_ACTION_SORT_PRIORITY, key=lambda k: _ACTION_SORT_PRIORITY[k])
)
_SORT_ORDER_NOTE = (
    f"Sorted by: status ({_ORDERED_ACTION_LABELS}), then most recently updated "
    "(chain boxes sorted by most recently updated PR in box)"
)
# LINT.ThenChange(//.agents/plugins/pr-queue/sidecars/pr_queue/index.html:action_needed_buckets)

_PASSING_CHECK_CONCLUSIONS = frozenset(
    {
        # keep-sorted start
        "NEUTRAL",
        "SKIPPED",
        "SUCCESS",
        # keep-sorted end
    }
)
_FAILING_CHECK_CONCLUSIONS = frozenset(
    {
        # keep-sorted start
        "ACTION_REQUIRED",
        "FAILURE",
        "STALE",
        "STARTUP_FAILURE",
        "TIMED_OUT",
        # keep-sorted end
    }
)
_FAILING_STATUS_STATES = frozenset(
    {
        # keep-sorted start
        "ERROR",
        "FAILURE",
        # keep-sorted end
    }
)
_PENDING_STATUS_STATES = frozenset(
    {
        # keep-sorted start
        "EXPECTED",
        "PENDING",
        # keep-sorted end
    }
)

_PROJECT_MEMBER_ASSOCIATIONS = frozenset(
    {
        # keep-sorted start
        "COLLABORATOR",
        "MEMBER",
        "OWNER",
        # keep-sorted end
    }
)

_DEFAULT_BASE_BRANCHES = frozenset(
    {
        # keep-sorted start
        "HEAD",
        "main",
        "master",
        # keep-sorted end
    }
)
_EMPTY_PARENT_MAP: Mapping[int, Sequence[int]] = {}
_HTML_COMMENT_RE = re.compile(r"<!--.*?-->", re.DOTALL)
_FENCED_CODE_RE = re.compile(r"(`{3,}|~{3,}).*?\1", re.DOTALL)
_INLINE_CODE_RE = re.compile(r"`[^`\n]+`")
_MARKDOWN_PR_LINK_RE = re.compile(
    r"\[[^\]]*\]\(https?://github\.com/"
    r"(?P<slug>[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)/pull/(?P<num>\d+)"
    r"(?:[/?#][^)\s]*)?\)"
)
_BARE_PR_URL_RE = re.compile(
    r"https?://github\.com/"
    r"(?P<slug>[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)/pull/(?P<num>\d+)"
    r"(?:[/?#][^\s),.;]*)?"
)
_DEPENDENCY_LEAD_IN_RE = re.compile(
    r"\b(?:"
    r"do\s+not\s+merge\s*[:,-]?\s*(?:awaiting|waiting\s+(?:on|for))"
    r"|awaiting"
    r"|waiting\s+(?:on|for)"
    r"|depends?\s+(?:on|upon)"
    r"|dependent\s+(?:on|upon)"
    r"|blocked\s+(?:by|on)"
    r"|stacked\s+(?:on(?:\s+top\s+of)?|atop)"
    r"|based\s+(?:on|upon)"
    r"|(?:builds?|built)\s+(?:on(?:\s+top\s+of)?|upon)"
    r"|on\s+top\s+of"
    r"|requires?"
    r"|prerequisites?"
    r"|(?:parent|base)\s+(?:pull\s+requests?|prs?)"
    r"|parent\s*:"
    r"|(?:merge|review|land)\s+after"
    r")"
    r"(?:\s+(?:pull\s+requests?|prs?))?\s*[:=-]?\s*"
    r"(?P<tail>[^\n.;]+)",
    re.IGNORECASE,
)
_LEADING_PR_REF_RE = re.compile(
    r"^\s*[*_]*(?:(?P<slug>[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+))?#(?P<num>\d+)\b[*_]*"
)
_REF_LIST_SEP_RE = re.compile(
    r"^\s*(?:,\s*(?:and\b)?|\band\b|&)\s*(?:(?:pull\s+requests?|prs?)\s+)?",
    re.IGNORECASE,
)
_GHSTACK_BULLET_RE = re.compile(
    r"^\s*[*+-]\s+(?:__->__\s+|\*\*->\*\*\s+|->\s+)?"
    r"[*_]*(?:(?P<slug>[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+))?#(?P<num>\d+)\b"
)
_NUMBERED_STACK_HEADER_RE = re.compile(
    r"^\s*#{0,6}\s*[*_]*(?:pr\s+|pull\s+request\s+)?stack[*_]*\s*:?\s*$",
    re.IGNORECASE,
)
_NUMBERED_STACK_ITEM_RE = re.compile(
    r"^\s*\d+[.)]\s+(?:[*_]|->|\s)*"
    r"(?:(?P<slug>[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+))?#(?P<num>\d+)\b"
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

_GRAPHQL_PR_METADATA_FIELDS = """
        number
        authorAssociation
        stack {
          number
          size
        }
        stackEntry {
          position
        }
        commits(last: 1) {
          nodes {
            commit {
              statusCheckRollup {
                contexts(first: 0) {
                  totalCount
                  checkRunCountsByState {
                    state
                    count
                  }
                  statusContextCountsByState {
                    state
                    count
                  }
                }
              }
            }
          }
        }
""".strip()

_GRAPHQL_PR_METADATA_QUERY = f"""
query($owner: String!, $name: String!, $limit: Int!) {{
  repository(owner: $owner, name: $name) {{
    pullRequests(
      states: OPEN,
      first: $limit,
      orderBy: {{field: CREATED_AT, direction: DESC}}
    ) {{
      nodes {{
        {_GRAPHQL_PR_METADATA_FIELDS}
      }}
    }}
  }}
}}
""".strip()

_GRAPHQL_SEARCH_METADATA_QUERY = f"""
query($searchQuery: String!, $limit: Int!) {{
  search(query: $searchQuery, type: ISSUE, first: $limit) {{
    nodes {{
      ... on PullRequest {{
        {_GRAPHQL_PR_METADATA_FIELDS}
      }}
    }}
  }}
}}
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


def _resolve_overall_checks_state(
    *, passed: int, failed: int, pending: int, cancelled: int
) -> str:
    # LINT.IfChange(checks_state_values)
    if failed > 0:
        return "failing"
    if pending > 0:
        return "pending"
    if cancelled > 0 and passed == 0:
        return "cancelled"
    if passed > 0 or cancelled > 0:
        return "passing"
    return "none"
    # LINT.ThenChange(//.agents/plugins/pr-queue/sidecars/pr_queue/index.html:checks_state_values)


def _summarize_checks(raw_rollup: object) -> tuple[str, int, int, int, int]:
    """Summarizes statusCheckRollup entries into aggregate CI counts.

    Args:
      raw_rollup: Raw `statusCheckRollup` value decoded from `gh pr view` JSON.

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
            elif state in _FAILING_STATUS_STATES:
                failed += 1
            elif state in _PENDING_STATUS_STATES:
                pending += 1
            continue

        status = str(item.get("status") or "").upper()
        conclusion = str(item.get("conclusion") or "").upper()
        if status and status != "COMPLETED":
            pending += 1
        elif conclusion in _PASSING_CHECK_CONCLUSIONS:
            passed += 1
        elif conclusion == "CANCELLED":
            cancelled += 1
        elif conclusion in _FAILING_CHECK_CONCLUSIONS:
            failed += 1
        elif not conclusion:
            pending += 1

    overall = _resolve_overall_checks_state(
        passed=passed, failed=failed, pending=pending, cancelled=cancelled
    )
    return (overall, passed, failed, pending, total)


def _summarize_graphql_checks(
    rollup_obj: object,
) -> tuple[str, int, int, int, int] | None:
    """Summarizes GraphQL `statusCheckRollup` aggregate counts without per-run fan-out."""
    if not isinstance(rollup_obj, dict):
        return None
    contexts_obj = rollup_obj.get("contexts")
    if not isinstance(contexts_obj, dict):
        return ("none", 0, 0, 0, 0)

    passed = 0
    failed = 0
    pending = 0
    cancelled = 0

    raw_check_counts = contexts_obj.get("checkRunCountsByState")
    if isinstance(raw_check_counts, list):
        for entry in raw_check_counts:
            if not isinstance(entry, dict):
                continue
            state = str(entry.get("state") or "").upper()
            count = _int_field(entry, "count")
            if count <= 0:
                continue
            if state in _PASSING_CHECK_CONCLUSIONS:
                passed += count
            elif state == "CANCELLED":
                cancelled += count
            elif state in _FAILING_CHECK_CONCLUSIONS:
                failed += count
            else:
                pending += count

    raw_status_counts = contexts_obj.get("statusContextCountsByState")
    if isinstance(raw_status_counts, list):
        for entry in raw_status_counts:
            if not isinstance(entry, dict):
                continue
            state = str(entry.get("state") or "").upper()
            count = _int_field(entry, "count")
            if count <= 0:
                continue
            if state == "SUCCESS":
                passed += count
            elif state in _FAILING_STATUS_STATES:
                failed += count
            elif state in _PENDING_STATUS_STATES:
                pending += count

    counted_total = passed + failed + pending + cancelled
    reported_total = _int_field(contexts_obj, "totalCount")
    total = max(counted_total, reported_total)
    if total <= 0:
        return ("none", 0, 0, 0, 0)
    overall = _resolve_overall_checks_state(
        passed=passed, failed=failed, pending=pending, cancelled=cancelled
    )
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


def _is_stackable_branch(branch: str) -> bool:
    if not branch or branch in _DEFAULT_BASE_BRANCHES:
        return False
    return not (branch.startswith("release/") or branch.startswith("release-"))


def _append_same_repo_dep(
    out: list[int],
    *,
    slug: str | None,
    raw_num: str,
    repo_lower: str,
    self_number: int,
) -> None:
    if slug and slug.lower() != repo_lower:
        return
    num = int(raw_num)
    if num <= 0 or num == self_number or num in out:
        return
    out.append(num)


def _strip_code_and_comments(body: str) -> str:
    without_comments = _HTML_COMMENT_RE.sub(" ", body)
    without_fenced = _FENCED_CODE_RE.sub("\n", without_comments)
    return _INLINE_CODE_RE.sub(" ", without_fenced)


def _extract_ghstack_parent(
    lines: Sequence[str], *, repo_lower: str, self_number: int
) -> list[int]:
    """Extracts the immediate parent PR from a `ghstack` bullet list.

    Args:
      lines: Cleaned Markdown body split into lines.
      repo_lower: Lowercased `owner/name` repository slug.
      self_number: Current PR number to locate in the stack list.

    Returns:
      Single-element list with the parent PR number, or empty list.
    """
    ghstack_items: list[tuple[str | None, str]] = []
    for line in lines:
        bullet_match = _GHSTACK_BULLET_RE.match(line)
        if bullet_match:
            ghstack_items.append(
                (bullet_match.group("slug"), bullet_match.group("num"))
            )
    deps: list[int] = []
    for idx, (slug, raw_num) in enumerate(ghstack_items):
        if slug and slug.lower() != repo_lower:
            continue
        if int(raw_num) == self_number and idx + 1 < len(ghstack_items):
            parent_slug, parent_num = ghstack_items[idx + 1]
            _append_same_repo_dep(
                deps,
                slug=parent_slug,
                raw_num=parent_num,
                repo_lower=repo_lower,
                self_number=self_number,
            )
            break
    return deps


def _extract_numbered_stack_parent(
    lines: Sequence[str], *, repo_lower: str, self_number: int
) -> list[int]:
    """Extracts the preceding parent PR from a numbered `Stack:` section.

    Args:
      lines: Cleaned Markdown body split into lines.
      repo_lower: Lowercased `owner/name` repository slug.
      self_number: Current PR number to locate in the numbered list.

    Returns:
      Single-element list with the parent PR number, or empty list.
    """
    in_numbered_stack = False
    numbered_items: list[tuple[str | None, str]] = []
    for line in lines:
        if _NUMBERED_STACK_HEADER_RE.match(line):
            in_numbered_stack = True
            numbered_items = []
            continue
        if not in_numbered_stack:
            continue
        if not line.strip():
            if numbered_items:
                break
            continue
        item_match = _NUMBERED_STACK_ITEM_RE.match(line)
        if not item_match:
            break
        numbered_items.append((item_match.group("slug"), item_match.group("num")))

    deps: list[int] = []
    for idx, (slug, raw_num) in enumerate(numbered_items):
        if slug and slug.lower() != repo_lower:
            continue
        if int(raw_num) == self_number and idx > 0:
            parent_slug, parent_num = numbered_items[idx - 1]
            _append_same_repo_dep(
                deps,
                slug=parent_slug,
                raw_num=parent_num,
                repo_lower=repo_lower,
                self_number=self_number,
            )
            break
    return deps


def _extract_stack_list_dependencies(
    cleaned_body: str, *, repo_lower: str, self_number: int
) -> list[int]:
    """Extracts parent PR numbers from `ghstack` or numbered `Stack:` lists."""
    if self_number <= 0:
        return []
    lines = cleaned_body.splitlines()
    deps: list[int] = []
    lower_body = cleaned_body.lower()
    if "stack from" in lower_body and "ghstack" in lower_body:
        deps.extend(
            _extract_ghstack_parent(
                lines, repo_lower=repo_lower, self_number=self_number
            )
        )
    for num in _extract_numbered_stack_parent(
        lines, repo_lower=repo_lower, self_number=self_number
    ):
        if num not in deps:
            deps.append(num)
    return deps


def extract_body_dependencies(
    body: str, *, repo: str, self_number: int = 0
) -> tuple[int, ...]:
    """Extracts parent PR numbers referenced by dependency text in a PR body.

    Args:
      body: Raw Markdown pull request description.
      repo: Target repository slug (`owner/name`) for cross-repo filtering.
      self_number: Current PR number excluded from self-references.

    Returns:
      Ordered tuple of unique positive parent PR numbers in `repo`.
    """
    if not body or not body.strip():
        return ()
    repo_lower = repo.strip().lower()
    cleaned = _strip_code_and_comments(body)
    normalized = _MARKDOWN_PR_LINK_RE.sub(r"\g<slug>#\g<num>", cleaned)
    normalized = _BARE_PR_URL_RE.sub(r"\g<slug>#\g<num>", normalized)

    deps: list[int] = []
    for clause_match in _DEPENDENCY_LEAD_IN_RE.finditer(normalized):
        tail = clause_match.group("tail")
        while tail:
            ref_match = _LEADING_PR_REF_RE.match(tail)
            if not ref_match:
                break
            _append_same_repo_dep(
                deps,
                slug=ref_match.group("slug"),
                raw_num=ref_match.group("num"),
                repo_lower=repo_lower,
                self_number=self_number,
            )
            tail = tail[ref_match.end() :]
            sep_match = _REF_LIST_SEP_RE.match(tail)
            if not sep_match:
                break
            tail = tail[sep_match.end() :]

    for list_dep in _extract_stack_list_dependencies(
        normalized, repo_lower=repo_lower, self_number=self_number
    ):
        if list_dep not in deps:
            deps.append(list_dep)
    return tuple(deps)


def normalize_pr(
    raw_pr: Mapping[str, object],
    *,
    repo: str,
    viewer: str,
    max_age_days: int,
    now: datetime.datetime,
    author_association: str = "",
    stack_number: int = 0,
    stack_position: int = 0,
    stack_size: int = 0,
    checks_summary: tuple[str, int, int, int, int] | None = None,
) -> PrSummary:
    """Converts a single `gh pr list` or `gh pr view` JSON item into a PrSummary.

    Args:
      raw_pr: Parsed JSON object for one PR from `gh pr list` or `gh pr view`.
      repo: Repository slug in `owner/name` form.
      viewer: Active GitHub login for viewer-scoped fields.
      max_age_days: Days since last update after which PRs are marked stale.
      now: Reference UTC timestamp used to compute age fields.
      author_association: Optional GraphQL `authorAssociation` override.
      stack_number: Optional GitHub PR stack number from GraphQL.
      stack_position: Optional 1-based position within the GitHub PR stack.
      stack_size: Optional total PR count in the GitHub PR stack.
      checks_summary: Optional `(state, passed, failed, pending, total)` from GraphQL.

    Returns:
      Normalized immutable PrSummary instance.
    """
    pr_number = _int_field(raw_pr, "number")
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

    raw_rollup = raw_pr.get("statusCheckRollup")
    has_rollup = isinstance(raw_rollup, list) and bool(raw_rollup)
    if checks_summary is not None and not has_rollup:
        checks_state, checks_passed, checks_failed, checks_pending, checks_total = (
            checks_summary
        )
    else:
        checks_state, checks_passed, checks_failed, checks_pending, checks_total = (
            _summarize_checks(raw_rollup)
        )

    is_draft = bool(raw_pr.get("isDraft"))
    is_cross_repo = bool(raw_pr.get("isCrossRepository"))
    pr_state = str(raw_pr.get("state") or "OPEN").strip().upper() or "OPEN"
    review_decision = str(raw_pr.get("reviewDecision") or "").upper() or "NONE"
    is_my_pr = bool(viewer_lower and author_login.lower() == viewer_lower)
    body_deps = extract_body_dependencies(
        str(raw_pr.get("body") or ""), repo=repo, self_number=pr_number
    )

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
        number=pr_number,
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
        is_cross_repository=is_cross_repo,
        depends_on=body_deps,
        stack_number=max(0, stack_number),
        stack_position=max(0, stack_position),
        stack_size=max(0, stack_size),
    )


def _updated_epoch(timestamp: str) -> float:
    if not timestamp:
        return 0.0
    try:
        return parse_iso_timestamp(timestamp).timestamp()
    except ValueError:
        return 0.0


def _own_sort_key(pr: PrSummary) -> tuple[int, float, int]:
    return (
        _ACTION_SORT_PRIORITY.get(pr.action_needed, _DEFAULT_ACTION_PRIORITY),
        -_updated_epoch(pr.updated_at),
        -pr.number,
    )


def _build_dependency_graph(
    prs: Sequence[PrSummary],
    extra_parents: Mapping[int, Sequence[int]],
) -> tuple[list[set[int]], list[set[int]]]:
    """Builds `(children, parents)` index adjacency sets over `prs`."""
    n = len(prs)
    children: list[set[int]] = [set() for _ in range(n)]
    parents: list[set[int]] = [set() for _ in range(n)]

    num_to_indices: dict[int, list[int]] = {}
    head_to_indices: dict[str, list[int]] = {}
    parent_lookup: dict[int, list[int]] = {
        num: list(deps) for num, deps in extra_parents.items()
    }
    stack_members: dict[int, list[tuple[int, int, int]]] = {}

    for idx, pr in enumerate(prs):
        num_to_indices.setdefault(pr.number, []).append(idx)
        merged_deps = parent_lookup.setdefault(pr.number, [])
        for dep in pr.depends_on:
            if dep not in merged_deps:
                merged_deps.append(dep)
        if not pr.is_cross_repository and _is_stackable_branch(pr.head_ref_name):
            head_to_indices.setdefault(pr.head_ref_name, []).append(idx)
        if pr.stack_number > 0 and pr.stack_position > 0:
            stack_members.setdefault(pr.stack_number, []).append(
                (pr.stack_position, pr.number, idx)
            )

    def add_edge(parent_idx: int, child_idx: int) -> None:
        if parent_idx == child_idx:
            return
        children[parent_idx].add(child_idx)
        parents[child_idx].add(parent_idx)

    for child_idx, pr in enumerate(prs):
        queue = deque(parent_lookup.get(pr.number, ()))
        seen_nums = {pr.number}
        while queue:
            anc_num = queue.popleft()
            if anc_num in seen_nums:
                continue
            seen_nums.add(anc_num)
            visible_parents = num_to_indices.get(anc_num)
            if visible_parents:
                for parent_idx in visible_parents:
                    add_edge(parent_idx, child_idx)
                continue
            queue.extend(parent_lookup.get(anc_num, ()))

        if _is_stackable_branch(pr.base_ref_name):
            for parent_idx in head_to_indices.get(pr.base_ref_name, ()):
                add_edge(parent_idx, child_idx)

    for members in stack_members.values():
        ordered_members = sorted(members)
        for pos_idx in range(len(ordered_members) - 1):
            curr_pos, _curr_num, curr_i = ordered_members[pos_idx]
            for next_idx in range(pos_idx + 1, len(ordered_members)):
                next_pos, _next_num, next_i = ordered_members[next_idx]
                if next_pos > curr_pos:
                    add_edge(curr_i, next_i)
                    break

    return (children, parents)


def _toposort_component(
    prs: Sequence[PrSummary],
    comp: Sequence[int],
    children: Sequence[set[int]],
    parents: Sequence[set[int]],
    own_keys: Sequence[tuple[int, float, int]],
) -> list[PrSummary]:
    """Orders a connected dependency component with parents higher than children."""
    comp_set = set(comp)
    effective_keys: dict[int, tuple[int, float, int]] = {}
    for idx in comp:
        comp_children = children[idx] & comp_set
        if not comp_children:
            effective_keys[idx] = own_keys[idx]
            continue
        visited = {idx}
        stack = [idx]
        while stack:
            curr = stack.pop()
            for child_idx in children[curr] & comp_set:
                if child_idx not in visited:
                    visited.add(child_idx)
                    stack.append(child_idx)
        effective_keys[idx] = min(own_keys[j] for j in visited)

    in_degree = {idx: len(parents[idx] & comp_set) for idx in comp}
    ready_heap: list[tuple[tuple[int, float, int], tuple[int, float, int], int]] = []
    for idx in comp:
        if in_degree[idx] == 0:
            heapq.heappush(ready_heap, (effective_keys[idx], own_keys[idx], idx))

    emitted: set[int] = set()
    ordered: list[PrSummary] = []
    while len(ordered) < len(comp):
        if not ready_heap:
            # Break malformed dependency cycles deterministically by priority.
            best_idx = min(
                (i for i in comp if i not in emitted),
                key=lambda i: (effective_keys[i], own_keys[i], i),
            )
            heapq.heappush(
                ready_heap, (effective_keys[best_idx], own_keys[best_idx], best_idx)
            )
        _eff_key, _own_key, idx = heapq.heappop(ready_heap)
        if idx in emitted:
            continue
        emitted.add(idx)
        ordered.append(prs[idx])
        for child_idx in children[idx] & comp_set:
            if child_idx in emitted:
                continue
            in_degree[child_idx] -= 1
            if in_degree[child_idx] <= 0:
                heapq.heappush(
                    ready_heap,
                    (effective_keys[child_idx], own_keys[child_idx], child_idx),
                )
    return ordered


def sort_prs(
    prs: Sequence[PrSummary],
    *,
    extra_parents: Mapping[int, Sequence[int]] = _EMPTY_PARENT_MAP,
) -> list[PrSummary]:
    """Groups PR dependency chains into contiguous boxes and sorts by priority/recency.

    Each connected dependency chain is ordered topologically (parents higher
    than children) and assigned a shared positive `chain_id`, while standalone
    PRs receive `chain_id=0`. Multi-PR chain boxes and standalone PRs are sorted
    relative to one another by highest-priority status in the group, then by the
    most recently modified PR (`max(updated_at)`) within the group.

    Args:
      prs: Pull request summaries to sort.
      extra_parents: Optional map of PR number to direct parent PR numbers across
        all open PRs, preserving transitive links across filtered-out items.

    Returns:
      Deterministically ordered list of `PrSummary` items with `chain_id` set.
    """
    n = len(prs)
    if n == 0:
        return []
    if n == 1:
        only = prs[0]
        return [dataclasses.replace(only, chain_id=0) if only.chain_id != 0 else only]

    children, parents = _build_dependency_graph(prs, extra_parents)
    own_keys = [_own_sort_key(pr) for pr in prs]

    visited_comp = [False] * n
    used_chain_ids: set[int] = set()
    fallback_chain_id = 1
    grouped: list[tuple[tuple[int, float, int], list[PrSummary]]] = []

    for start_idx in range(n):
        if visited_comp[start_idx]:
            continue
        visited_comp[start_idx] = True
        comp = [start_idx]
        queue = deque([start_idx])
        while queue:
            curr = queue.popleft()
            for neighbor in children[curr] | parents[curr]:
                if not visited_comp[neighbor]:
                    visited_comp[neighbor] = True
                    comp.append(neighbor)
                    queue.append(neighbor)

        group_sort_key = (
            min(own_keys[i][0] for i in comp),
            min(own_keys[i][1] for i in comp),
            min(own_keys[i][2] for i in comp),
        )
        if len(comp) == 1:
            single = prs[comp[0]]
            if single.chain_id != 0:
                single = dataclasses.replace(single, chain_id=0)
            grouped.append((group_sort_key, [single]))
            continue

        ordered_comp = _toposort_component(prs, comp, children, parents, own_keys)
        preferred_id = ordered_comp[0].number
        if preferred_id > 0 and preferred_id not in used_chain_ids:
            cid = preferred_id
        else:
            while fallback_chain_id in used_chain_ids:
                fallback_chain_id += 1
            cid = fallback_chain_id
        used_chain_ids.add(cid)
        tagged_comp = [
            dataclasses.replace(pr, chain_id=cid) if pr.chain_id != cid else pr
            for pr in ordered_comp
        ]
        grouped.append((group_sort_key, tagged_comp))

    grouped.sort(key=lambda pair: pair[0])
    ordered_all: list[PrSummary] = []
    for _key, comp_prs in grouped:
        ordered_all.extend(comp_prs)
    return ordered_all


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
        _PR_LIST_JSON_FIELDS,
    ]
    if clean_query:
        args.append(f"--search={clean_query}")
    return args


def _build_graphql_metadata_args(
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
            f"query={_GRAPHQL_SEARCH_METADATA_QUERY}",
            "--raw-field",
            f"searchQuery={search_expr}",
            "--field",
            f"limit={gql_limit}",
        ]
    return [
        "api",
        "graphql",
        "--raw-field",
        f"query={_GRAPHQL_PR_METADATA_QUERY}",
        "--raw-field",
        f"owner={owner}",
        "--raw-field",
        f"name={name}",
        "--field",
        f"limit={gql_limit}",
    ]


def _extract_graphql_pr_nodes(data: Mapping[str, object]) -> object:
    repo_obj = data.get("repository")
    if isinstance(repo_obj, dict):
        prs_obj = repo_obj.get("pullRequests")
        if isinstance(prs_obj, dict):
            return prs_obj.get("nodes")
    search_obj = data.get("search")
    if isinstance(search_obj, dict):
        return search_obj.get("nodes")
    return None


def _extract_graphql_checks_summary(
    node: Mapping[str, object],
) -> tuple[str, int, int, int, int] | None:
    commits_obj = node.get("commits")
    if not isinstance(commits_obj, dict):
        return None
    commit_nodes = commits_obj.get("nodes")
    if not isinstance(commit_nodes, list) or not commit_nodes:
        return None
    first_node = commit_nodes[0]
    if not isinstance(first_node, dict):
        return None
    commit_obj = first_node.get("commit")
    if not isinstance(commit_obj, dict) or "statusCheckRollup" not in commit_obj:
        return None
    rollup_obj = commit_obj.get("statusCheckRollup")
    if rollup_obj is None:
        return ("none", 0, 0, 0, 0)
    return _summarize_graphql_checks(rollup_obj)


def _parse_graphql_pr_metadata(raw_output: str) -> dict[int, _PrGraphqlMeta]:
    try:
        parsed = json.loads(raw_output or "{}")
    except json.JSONDecodeError:
        return {}
    if not isinstance(parsed, dict):
        return {}
    data = parsed.get("data")
    if not isinstance(data, dict):
        return {}

    nodes = _extract_graphql_pr_nodes(data)
    if not isinstance(nodes, list):
        return {}

    metadata: dict[int, _PrGraphqlMeta] = {}
    for node in nodes:
        if not isinstance(node, dict) or "number" not in node:
            continue
        try:
            pr_num = int(node["number"])
        except (TypeError, ValueError):
            continue
        if pr_num <= 0:
            continue
        assoc = str(node.get("authorAssociation") or "").strip().upper()
        stack_number = 0
        stack_size = 0
        stack_position = 0
        stack_obj = node.get("stack")
        entry_obj = node.get("stackEntry")
        if isinstance(stack_obj, dict) and isinstance(entry_obj, dict):
            raw_stack_num = _int_field(stack_obj, "number")
            raw_stack_size = _int_field(stack_obj, "size")
            raw_stack_pos = _int_field(entry_obj, "position")
            if raw_stack_num > 0 and raw_stack_pos > 0:
                stack_number = raw_stack_num
                stack_position = raw_stack_pos
                stack_size = max(raw_stack_size, raw_stack_pos)
        checks_summary = _extract_graphql_checks_summary(node)
        if assoc or stack_number > 0 or checks_summary is not None:
            metadata[pr_num] = _PrGraphqlMeta(
                author_association=assoc,
                stack_number=stack_number,
                stack_position=stack_position,
                stack_size=stack_size,
                checks_summary=checks_summary,
            )
    return metadata


def _attach_structural_dependencies(
    summaries: Sequence[PrSummary],
) -> tuple[list[PrSummary], dict[int, tuple[int, ...]]]:
    """Resolves GitHub stack and base-branch parent PR numbers across `summaries`."""
    same_repo_head_to_num: dict[str, int] = {}
    stack_groups: dict[int, list[PrSummary]] = {}
    for pr in summaries:
        if not pr.is_cross_repository and _is_stackable_branch(pr.head_ref_name):
            same_repo_head_to_num.setdefault(pr.head_ref_name, pr.number)
        if pr.stack_number > 0 and pr.stack_position > 0:
            stack_groups.setdefault(pr.stack_number, []).append(pr)

    stack_parent_of: dict[int, int] = {}
    for group in stack_groups.values():
        ordered_group = sorted(group, key=lambda p: (p.stack_position, p.number))
        for idx in range(1, len(ordered_group)):
            prev_pr = ordered_group[idx - 1]
            curr_pr = ordered_group[idx]
            if curr_pr.stack_position > prev_pr.stack_position:
                stack_parent_of[curr_pr.number] = prev_pr.number

    resolved: list[PrSummary] = []
    all_open_parents: dict[int, tuple[int, ...]] = {}
    for pr in summaries:
        combined: list[int] = []
        stack_parent = stack_parent_of.get(pr.number, 0)
        if stack_parent > 0 and stack_parent != pr.number:
            combined.append(stack_parent)
        if _is_stackable_branch(pr.base_ref_name):
            branch_parent = same_repo_head_to_num.get(pr.base_ref_name, 0)
            if (
                branch_parent > 0
                and branch_parent != pr.number
                and branch_parent not in combined
            ):
                combined.append(branch_parent)
        for body_dep in pr.depends_on:
            if body_dep not in combined and body_dep != pr.number:
                combined.append(body_dep)
        deps_tuple = tuple(combined)
        updated_pr = pr
        if deps_tuple != pr.depends_on:
            updated_pr = dataclasses.replace(pr, depends_on=deps_tuple)
        resolved.append(updated_pr)
        all_open_parents[updated_pr.number] = deps_tuple
    return (resolved, all_open_parents)


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
    graphql_metadata: Mapping[int, _PrGraphqlMeta],
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
      graphql_metadata: Map of PR number to GraphQL role and stack metadata.

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
    default_meta = _PrGraphqlMeta()

    raw_summaries: list[PrSummary] = []
    for item in raw_items:
        if not isinstance(item, dict) or "number" not in item:
            continue
        pr_num = int(item["number"])
        meta = graphql_metadata.get(pr_num, default_meta)
        raw_summaries.append(
            normalize_pr(
                item,
                repo=clean_repo,
                viewer=viewer,
                max_age_days=max(0, max_age_days),
                now=current_time,
                author_association=meta.author_association,
                stack_number=meta.stack_number,
                stack_position=meta.stack_position,
                stack_size=meta.stack_size,
                checks_summary=meta.checks_summary,
            )
        )

    summaries, all_open_parents = _attach_structural_dependencies(raw_summaries)

    active_prs: list[PrSummary] = []
    stale_prs: list[PrSummary] = []
    skipped_drafts = 0
    skipped_authored = 0
    skipped_approved = 0

    for summary in summaries:
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
        prs=sort_prs(active_prs, extra_parents=all_open_parents),
        stale_prs=sort_prs(stale_prs, extra_parents=all_open_parents),
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
    gql_args = _build_graphql_metadata_args(clean_repo, clean_query, limit)

    list_coro = runner(args, _GH_LIST_TIMEOUT_SECONDS)
    gql_coro = (
        runner(gql_args, _GH_LIST_TIMEOUT_SECONDS)
        if gql_args is not None
        else _ready_value("{}")
    )
    user_coro = (
        get_current_gh_user_async(runner=runner) if not viewer else _ready_value(viewer)
    )

    raw_output, gql_res, viewer_res = await asyncio.gather(
        list_coro, gql_coro, user_coro, return_exceptions=True
    )
    if isinstance(viewer_res, BaseException):
        raise viewer_res
    if isinstance(raw_output, BaseException):
        raise raw_output
    if isinstance(gql_res, FetchError):
        # GraphQL membership, stack, and check metadata are advisory; degrade safely.
        _LOGGER.warning(
            "GraphQL metadata lookup failed: %s",
            sanitize_log_text(gql_res),
        )
        graphql_metadata: dict[int, _PrGraphqlMeta] = {}
    elif isinstance(gql_res, BaseException):
        raise gql_res
    else:
        graphql_metadata = _parse_graphql_pr_metadata(gql_res)

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
        graphql_metadata=graphql_metadata,
    )


def _format_markdown_entry(pr: PrSummary, *, detailed: bool) -> str:
    member_tag = " [member]" if pr.is_project_member else ""
    if not detailed:
        return (
            f"- **#{pr.number}** {pr.title} (@{pr.author}{member_tag}, "
            f"{pr.days_since_update}d) — {pr.url}"
        )
    req_tag = " [review-requested]" if pr.review_requested_from_me else ""
    checks_tag = f"checks={pr.checks_state}"
    return (
        f"- **#{pr.number}** [{pr.action_needed}{req_tag}] "
        f"{pr.title} (@{pr.author}{member_tag}, "
        f"{pr.days_since_update}d since update, "
        f"{checks_tag}) — {pr.url}"
    )


def _append_markdown_pr_list(
    lines: list[str], prs: Sequence[PrSummary], *, detailed: bool
) -> None:
    idx = 0
    total = len(prs)
    while idx < total:
        pr = prs[idx]
        if pr.chain_id > 0:
            end_idx = idx + 1
            while end_idx < total and prs[end_idx].chain_id == pr.chain_id:
                end_idx += 1
            if end_idx - idx >= 2:
                lines.append("----")
                for chain_pr in prs[idx:end_idx]:
                    lines.append(_format_markdown_entry(chain_pr, detailed=detailed))
                lines.append("----")
                idx = end_idx
                continue
        lines.append(_format_markdown_entry(pr, detailed=detailed))
        idx += 1


def format_markdown(result: PrQueueResult) -> str:
    """Formats a PrQueueResult as concise Markdown for terminal inspection."""
    lines = [
        f"# PR Queue: {result.repo} (viewer: {result.viewer})",
        "",
        (
            f"Active: {len(result.prs)} | Stale (>{result.max_age_days}d): "
            f"{len(result.stale_prs)} | Skipped drafts: {result.skipped_drafts}"
        ),
        _SORT_ORDER_NOTE,
        "",
    ]
    if not result.prs:
        lines.append("No matching open pull requests.")
    else:
        _append_markdown_pr_list(lines, result.prs, detailed=True)
    if result.stale_prs:
        lines.extend(["", f"## Stale (>{result.max_age_days} days since update)", ""])
        _append_markdown_pr_list(lines, result.stale_prs, detailed=False)
    return "\n".join(lines) + "\n"


# =============================================================================
# 4. Classes
# =============================================================================


class FetchError(Exception):
    """Raised when querying GitHub pull requests fails."""


@dataclasses.dataclass(frozen=True)
class _PrGraphqlMeta:
    """Supplemental per-PR role and stack metadata fetched from GitHub GraphQL."""

    # Author repository association (OWNER, MEMBER, COLLABORATOR, etc.).
    author_association: str = ""
    # Native GitHub PR stack number, or 0 when not in a stack.
    stack_number: int = 0
    # 1-based position of this PR in its GitHub stack, or 0 when unstacked.
    stack_position: int = 0
    # Total number of entries in the GitHub stack, or 0 when unstacked.
    stack_size: int = 0
    # Aggregate CI check summary `(state, passed, failed, pending, total)`, or None.
    checks_summary: tuple[str, int, int, int, int] | None = None


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
    # Whether head_ref_name comes from an external fork rather than repo.
    is_cross_repository: bool = False
    # Direct parent PR numbers in repo that this PR depends on.
    depends_on: tuple[int, ...] = ()
    # Native GitHub PR stack number, or 0 when not in a GitHub stack.
    stack_number: int = 0
    # 1-based position of this PR in its GitHub stack, or 0 when unstacked.
    stack_position: int = 0
    # Total number of entries in the GitHub stack, or 0 when unstacked.
    stack_size: int = 0
    # Shared positive ID for PRs in a multi-PR dependency chain, or 0 when standalone.
    chain_id: int = 0

    def to_dict(self) -> dict[str, object]:
        """Serializes this summary into a JSON-compatible dict."""
        data: dict[str, object] = dataclasses.asdict(self)
        tuple_fields = (
            "requested_reviewers",
            "approved_by",
            "changes_requested_by",
            "labels",
            "depends_on",
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
