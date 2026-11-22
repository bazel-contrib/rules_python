#!/usr/bin/env python3
"""Unit tests for fetch_pr_queue.py."""

from __future__ import annotations

import asyncio
import datetime
import io
import json
import unittest
from collections.abc import Sequence
from unittest import mock

import fetch_pr_queue


def _make_raw_pr(
    number: int,
    *,
    title: str = "Sample PR",
    author: str = "contributor",
    updated_at: str = "2026-11-10T10:00:00Z",
    created_at: str = "2026-11-08T10:00:00Z",
    is_draft: bool = False,
    review_decision: str = "REVIEW_REQUIRED",
    review_requests: list[dict[str, object]] | None = None,
    latest_reviews: list[dict[str, object]] | None = None,
    status_rollup: list[dict[str, object]] | None = None,
) -> dict[str, object]:
    return {
        "number": number,
        "title": title,
        "url": f"https://github.com/bazel-contrib/rules_python/pull/{number}",
        "author": {"login": author, "is_bot": False},
        "createdAt": created_at,
        "updatedAt": updated_at,
        "headRefName": f"branch-{number}",
        "headRefOid": f"deadbeef{number:04d}",
        "baseRefName": "main",
        "isDraft": is_draft,
        "reviewDecision": review_decision,
        "reviewRequests": review_requests or [],
        "reviews": [],
        "latestReviews": latest_reviews or [],
        "additions": 10,
        "deletions": 2,
        "changedFiles": 1,
        "labels": [{"name": "bug"}],
        "statusCheckRollup": status_rollup or [],
    }


class TimestampParsingTest(unittest.TestCase):
    """Tests ISO 8601 parsing and day age computation."""

    def test_parses_utc_z_suffix(self) -> None:
        parsed = fetch_pr_queue.parse_iso_timestamp("2026-11-10T12:30:00Z")
        self.assertEqual(
            parsed,
            datetime.datetime(2026, 11, 10, 12, 30, 0, tzinfo=datetime.UTC),
        )

    def test_computes_non_negative_age_days(self) -> None:
        now = datetime.datetime(2026, 11, 12, 12, 0, 0, tzinfo=datetime.UTC)
        self.assertEqual(
            fetch_pr_queue.compute_age_days("2026-11-10T11:00:00Z", now), 2
        )
        self.assertEqual(
            fetch_pr_queue.compute_age_days("2026-11-13T00:00:00Z", now), 0
        )


class FetchPrQueueTest(unittest.IsolatedAsyncioTestCase):
    """Tests filtering, normalization, check summarization, sorting, and CLI."""

    def setUp(self) -> None:
        self.now = datetime.datetime(2026, 11, 12, 12, 0, 0, tzinfo=datetime.UTC)

    async def test_filters_drafts_authored_approved_and_stale(self) -> None:
        raw_prs = [
            _make_raw_pr(1, is_draft=True),
            _make_raw_pr(2, author="rickeylev"),
            _make_raw_pr(
                3,
                latest_reviews=[
                    {"author": {"login": "rickeylev"}, "state": "APPROVED"}
                ],
                review_decision="APPROVED",
            ),
            _make_raw_pr(
                4,
                title="Stale PR",
                updated_at="2026-09-01T00:00:00Z",
                created_at="2026-08-15T00:00:00Z",
            ),
            _make_raw_pr(
                5,
                title="Active requested PR",
                review_requests=[{"__typename": "User", "login": "rickeylev"}],
                status_rollup=[
                    {
                        "__typename": "CheckRun",
                        "status": "COMPLETED",
                        "conclusion": "SUCCESS",
                    },
                    {
                        "__typename": "CheckRun",
                        "status": "IN_PROGRESS",
                        "conclusion": "",
                    },
                ],
            ),
        ]

        recorded_cmds: list[list[str]] = []

        async def fake_runner(args: Sequence[str], _timeout: int) -> str:
            recorded_cmds.append(list(args))
            if list(args[:2]) == ["api", "user"]:
                return "rickeylev\n"
            if list(args[:2]) == ["api", "graphql"]:
                return "{}"
            return json.dumps(raw_prs)

        result = await fetch_pr_queue.fetch_pr_queue_async(
            repo="bazel-contrib/rules_python",
            max_age_days=30,
            custom_query="label:bug",
            runner=fake_runner,
            now=self.now,
        )

        self.assertEqual(result.viewer, "rickeylev")
        self.assertEqual(result.skipped_drafts, 1)
        self.assertEqual(result.skipped_authored, 1)
        self.assertEqual(result.skipped_approved, 1)
        self.assertEqual([pr.number for pr in result.prs], [5])
        self.assertEqual([pr.number for pr in result.stale_prs], [4])
        self.assertTrue(result.prs[0].review_requested_from_me)
        self.assertEqual(result.prs[0].action_needed, "review_requested")
        self.assertEqual(result.prs[0].checks_state, "pending")
        self.assertEqual(result.prs[0].checks_passed, 1)
        self.assertEqual(result.prs[0].checks_pending, 1)
        self.assertIn("--repo=bazel-contrib/rules_python", recorded_cmds[0])
        self.assertIn("--search=label:bug", recorded_cmds[0])

    async def test_sorts_by_action_priority_then_updated_desc(self) -> None:
        raw_prs = [
            _make_raw_pr(
                10,
                title="Changes requested",
                updated_at="2026-11-12T11:00:00Z",
                review_decision="CHANGES_REQUESTED",
                latest_reviews=[
                    {"author": {"login": "other"}, "state": "CHANGES_REQUESTED"}
                ],
            ),
            _make_raw_pr(
                11,
                title="Needs review older",
                updated_at="2026-11-10T09:00:00Z",
            ),
            _make_raw_pr(
                12,
                title="Needs review newer",
                updated_at="2026-11-12T09:00:00Z",
            ),
            _make_raw_pr(
                13,
                title="Explicitly requested",
                updated_at="2026-11-09T09:00:00Z",
                review_requests=[{"requestedReviewer": {"login": "rickeylev"}}],
            ),
        ]

        async def fake_runner(args: Sequence[str], _timeout: int) -> str:
            if list(args[:2]) == ["api", "graphql"]:
                return "{}"
            return json.dumps(raw_prs)

        result = await fetch_pr_queue.fetch_pr_queue_async(
            user="rickeylev",
            runner=fake_runner,
            now=self.now,
        )
        self.assertEqual([pr.number for pr in result.prs], [13, 12, 11, 10])

    async def test_summarizes_status_context_and_check_failures(self) -> None:
        raw_prs = [
            _make_raw_pr(
                20,
                status_rollup=[
                    {"__typename": "StatusContext", "state": "FAILURE"},
                    {
                        "__typename": "CheckRun",
                        "status": "COMPLETED",
                        "conclusion": "SUCCESS",
                    },
                ],
            )
        ]

        async def fake_runner(args: Sequence[str], _timeout: int) -> str:
            if list(args[:2]) == ["api", "graphql"]:
                return "{}"
            return json.dumps(raw_prs)

        result = await fetch_pr_queue.fetch_pr_queue_async(
            user="alice",
            runner=fake_runner,
            now=self.now,
        )
        pr = result.prs[0]
        self.assertEqual(pr.checks_state, "failing")
        self.assertEqual(pr.checks_failed, 1)
        self.assertEqual(pr.checks_passed, 1)
        self.assertEqual(pr.checks_total, 2)

    async def test_review_requested_only_filter(self) -> None:
        raw_prs = [
            _make_raw_pr(30),
            _make_raw_pr(
                31,
                review_requests=[{"__typename": "User", "login": "alice"}],
            ),
        ]

        async def fake_runner(args: Sequence[str], _timeout: int) -> str:
            if list(args[:2]) == ["api", "graphql"]:
                return "{}"
            return json.dumps(raw_prs)

        result = await fetch_pr_queue.fetch_pr_queue_async(
            user="alice",
            review_requested_only=True,
            runner=fake_runner,
            now=self.now,
        )
        self.assertEqual([pr.number for pr in result.prs], [31])

    async def test_raises_fetch_error_on_empty_repo_and_invalid_json(self) -> None:
        async def bad_json_runner(args: Sequence[str], _timeout: int) -> str:
            if list(args[:2]) == ["api", "graphql"]:
                return "{}"
            return "{not json"

        for invalid_repo in (
            "   ",
            "../evil",
            "owner/..",
            "-bad/repo",
            "owner/a b",
            "owner\n/name",
        ):
            with self.assertRaises(fetch_pr_queue.FetchError):
                await fetch_pr_queue.fetch_pr_queue_async(
                    repo=invalid_repo,
                    user="alice",
                    runner=bad_json_runner,
                    now=self.now,
                )

        for bad_query in (
            "label:bug\nauthor:evil",
            "label:bug\x85evil",
            'label:"unclosed',
            "label:(bug",
            "label:bug)",
        ):
            with self.assertRaises(fetch_pr_queue.FetchError):
                await fetch_pr_queue.fetch_pr_queue_async(
                    user="alice",
                    custom_query=bad_query,
                    runner=bad_json_runner,
                    now=self.now,
                )

        self.assertEqual(
            fetch_pr_queue.validate_search_query(
                '-author:app/dependabot label:"bug" (foo OR bar)',
                error_cls=fetch_pr_queue.FetchError,
            ),
            '-author:app/dependabot label:"bug" (foo OR bar)',
        )

        with self.assertRaises(fetch_pr_queue.FetchError):
            await fetch_pr_queue.fetch_pr_queue_async(
                user="alice",
                runner=bad_json_runner,
                now=self.now,
            )

    def test_main_emits_json_and_handles_errors(self) -> None:
        raw_prs = [_make_raw_pr(99, title="CLI PR")]
        stdout = io.StringIO()

        async def ok_runner(args: Sequence[str], _timeout: int) -> str:
            if list(args[:2]) == ["api", "graphql"]:
                return "{}"
            return json.dumps(raw_prs)

        with mock.patch.object(
            fetch_pr_queue,
            "run_gh_command_async",
            side_effect=ok_runner,
        ), mock.patch("sys.stdout", stdout):
            rc = fetch_pr_queue.main(["--user", "alice", "--json"])
        self.assertEqual(rc, 0)
        payload = json.loads(stdout.getvalue())
        self.assertEqual(payload["count"], 1)
        self.assertEqual(payload["prs"][0]["number"], 99)

        stderr = io.StringIO()
        with mock.patch.object(
            fetch_pr_queue,
            "run_gh_command_async",
            side_effect=fetch_pr_queue.FetchError("boom"),
        ), mock.patch("sys.stderr", stderr):
            rc_err = fetch_pr_queue.main(["--user", "alice"])
        self.assertEqual(rc_err, 1)
        self.assertIn("boom", stderr.getvalue())


class FetchPrQueueAsyncTest(unittest.IsolatedAsyncioTestCase):
    """Tests asyncio PR fetching wrapper."""

    async def test_fetches_and_resolves_user_and_membership(self) -> None:
        bot_pr = _make_raw_pr(406, title="Bot PR", author="dependabot[bot]")
        bot_pr["author"] = {"login": "dependabot[bot]", "is_bot": True}
        raw_prs = [
            _make_raw_pr(404, title="Member PR", author="aignas"),
            _make_raw_pr(405, title="External PR", author="newcomer"),
            bot_pr,
        ]
        gql_resp = {
            "data": {
                "repository": {
                    "pullRequests": {
                        "nodes": [
                            {"number": 404, "authorAssociation": "COLLABORATOR"},
                            {
                                "number": 405,
                                "authorAssociation": "FIRST_TIME_CONTRIBUTOR",
                            },
                            {"number": 406, "authorAssociation": "COLLABORATOR"},
                        ]
                    }
                }
            }
        }

        async def fake_runner(args: Sequence[str], _timeout: int) -> str:
            if list(args[:2]) == ["api", "user"]:
                return "rickeylev\n"
            if list(args[:2]) == ["api", "graphql"]:
                return json.dumps(gql_resp)
            return json.dumps(raw_prs)

        now = datetime.datetime(2026, 11, 12, 12, 0, 0, tzinfo=datetime.UTC)
        result = await fetch_pr_queue.fetch_pr_queue_async(runner=fake_runner, now=now)
        self.assertEqual(result.viewer, "rickeylev")
        by_num = {pr.number: pr for pr in result.prs}
        self.assertTrue(by_num[404].is_project_member)
        self.assertEqual(by_num[404].author_association, "COLLABORATOR")
        self.assertFalse(by_num[405].is_project_member)
        self.assertEqual(by_num[405].author_association, "FIRST_TIME_CONTRIBUTOR")
        self.assertFalse(by_num[406].is_project_member)
        md = fetch_pr_queue.format_markdown(result)
        self.assertIn("@aignas [member]", md)
        self.assertNotIn("@newcomer [member]", md)

    async def test_search_mode_and_graphql_failure_degrades_gracefully(self) -> None:
        raw_prs = [_make_raw_pr(500, title="Search PR", author="someone")]

        async def fake_runner(args: Sequence[str], _timeout: int) -> str:
            if list(args[:2]) == ["api", "graphql"]:
                raise fetch_pr_queue.FetchError("graphql flaky")
            return json.dumps(raw_prs)

        result = await fetch_pr_queue.fetch_pr_queue_async(
            user="rickeylev",
            custom_query="label:bug",
            runner=fake_runner,
            now=datetime.datetime(2026, 11, 12, 12, 0, 0, tzinfo=datetime.UTC),
        )
        self.assertEqual(len(result.prs), 1)
        self.assertFalse(result.prs[0].is_project_member)
        self.assertEqual(result.prs[0].author_association, "")

    async def test_graphql_cancellation_is_not_swallowed(self) -> None:
        async def cancelled_runner(args: Sequence[str], _timeout: int) -> str:
            if list(args[:2]) == ["api", "graphql"]:
                raise asyncio.CancelledError()
            return json.dumps([_make_raw_pr(501)])

        with self.assertRaises(asyncio.CancelledError):
            await fetch_pr_queue.fetch_pr_queue_async(
                user="rickeylev",
                runner=cancelled_runner,
                now=datetime.datetime(2026, 11, 12, 12, 0, 0, tzinfo=datetime.UTC),
            )

    async def test_retries_transient_502_and_fails_fast_on_auth_error(self) -> None:
        calls = 0

        async def flaky_once(_args: object, _timeout: int) -> str:
            nonlocal calls
            calls += 1
            if calls < 3:
                raise fetch_pr_queue.FetchError("HTTP 502: Bad Gateway")
            return "recovered\n"

        with mock.patch.object(
            fetch_pr_queue, "_run_gh_once_async", side_effect=flaky_once
        ), mock.patch.object(fetch_pr_queue.asyncio, "sleep", return_value=None):
            out = await fetch_pr_queue.run_gh_command_async(["api", "user"], 10)
        self.assertEqual(out, "recovered\n")
        self.assertEqual(calls, 3)

        auth_calls = 0

        async def auth_fail(_args: object, _timeout: int) -> str:
            nonlocal auth_calls
            auth_calls += 1
            raise fetch_pr_queue.FetchError("HTTP 401: Bad credentials")

        with mock.patch.object(
            fetch_pr_queue, "_run_gh_once_async", side_effect=auth_fail
        ), mock.patch.object(
            fetch_pr_queue.asyncio, "sleep", return_value=None
        ), self.assertRaises(fetch_pr_queue.FetchError):
            await fetch_pr_queue.run_gh_command_async(["api", "user"], 10)
        self.assertEqual(auth_calls, 1)

    def test_subprocess_error_uses_demarcated_blocks(self) -> None:
        msg = fetch_pr_queue.format_subprocess_error("gh pr list", 2, "out", "err")
        self.assertIn("==================== STDOUT BEGIN ====================", msg)
        self.assertIn("==================== STDOUT END ====================", msg)
        self.assertIn("==================== STDERR BEGIN ====================", msg)
        self.assertIn("==================== STDERR END ====================", msg)

    def test_sanitize_log_text_strips_ansi_and_control_chars(self) -> None:
        self.assertEqual(
            fetch_pr_queue.sanitize_log_text("\x1b[31merr\x1b[0m\r\nnext\x85line\x7f"),
            "err next line",
        )

    def test_normalize_pr_preserves_lifecycle_state(self) -> None:
        raw_merged = _make_raw_pr(60)
        raw_merged["state"] = "merged"
        summary = fetch_pr_queue.normalize_pr(
            raw_merged,
            repo="bazel-contrib/rules_python",
            viewer="alice",
            max_age_days=30,
            now=datetime.datetime(2026, 11, 12, 12, 0, 0, tzinfo=datetime.UTC),
        )
        self.assertEqual(summary.state, "MERGED")
        self.assertEqual(summary.to_dict()["state"], "MERGED")


if __name__ == "__main__":
    unittest.main()
