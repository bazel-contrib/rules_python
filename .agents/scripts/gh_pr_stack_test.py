#!/usr/bin/env python3
"""Unit tests for gh_pr_stack.py."""

from __future__ import annotations

import subprocess
import unittest
from unittest import mock

import gh_pr_stack

_SAMPLE_STACK_JSON = """{
  "number": 4513,
  "open": true,
  "base": {"ref": "main"},
  "pull_requests": [
    {
      "number": 4511,
      "draft": true,
      "state": "open",
      "head": {"ref": "rickeylev/shrubbery/01-py-wheel-dist"},
      "base": {"ref": "main"}
    },
    {
      "number": 4512,
      "draft": true,
      "state": "open",
      "head": {"ref": "rickeylev/shrubbery/02-py-console-script-gen"},
      "base": {"ref": "rickeylev/shrubbery/01-py-wheel-dist"}
    }
  ]
}"""


class GhPrStackTest(unittest.TestCase):
    def test_validate_repo_slug_accepts_valid_slug(self) -> None:
        self.assertEqual(
            gh_pr_stack.validate_repo_slug("bazel-contrib/rules_python"),
            "bazel-contrib/rules_python",
        )

    def test_validate_repo_slug_rejects_traversal_and_flags(self) -> None:
        for invalid in (
            "../foo",
            "owner/..",
            "-flag/repo",
            "owner/-repo",
            "bad",
            "owner/repo\n",
        ):
            with self.subTest(invalid=invalid):
                with self.assertRaises(ValueError):
                    gh_pr_stack.validate_repo_slug(invalid)

    @mock.patch.object(subprocess, "run", autospec=True)
    def test_create_invokes_gh_api(self, mock_run: mock.MagicMock) -> None:
        mock_run.return_value = subprocess.CompletedProcess(
            args=[], returncode=0, stdout=_SAMPLE_STACK_JSON, stderr=""
        )
        rc = gh_pr_stack.main(["create", "4511", "4512"])
        self.assertEqual(rc, 0)
        mock_run.assert_called_once_with(
            [
                "gh",
                "api",
                "-H",
                "Accept: application/vnd.github+json",
                "-X",
                "POST",
                "repos/bazel-contrib/rules_python/stacks",
                "-F=pull_requests[]=4511",
                "-F=pull_requests[]=4512",
            ],
            capture_output=True,
            text=True,
            check=True,
        )

    def test_create_requires_at_least_two_prs(self) -> None:
        with self.assertRaises(ValueError):
            gh_pr_stack.main(["create", "4511"])

    @mock.patch.object(subprocess, "run", autospec=True)
    def test_add_invokes_add_endpoint(self, mock_run: mock.MagicMock) -> None:
        mock_run.return_value = subprocess.CompletedProcess(
            args=[], returncode=0, stdout=_SAMPLE_STACK_JSON, stderr=""
        )
        rc = gh_pr_stack.main(["add", "4513", "4514", "4515"])
        self.assertEqual(rc, 0)
        mock_run.assert_called_once_with(
            [
                "gh",
                "api",
                "-H",
                "Accept: application/vnd.github+json",
                "-X",
                "POST",
                "repos/bazel-contrib/rules_python/stacks/4513/add",
                "-F=pull_requests[]=4514",
                "-F=pull_requests[]=4515",
            ],
            capture_output=True,
            text=True,
            check=True,
        )

    @mock.patch.object(subprocess, "run", autospec=True)
    def test_unstack_invokes_unstack_endpoint(self, mock_run: mock.MagicMock) -> None:
        mock_run.return_value = subprocess.CompletedProcess(
            args=[], returncode=0, stdout=_SAMPLE_STACK_JSON, stderr=""
        )
        rc = gh_pr_stack.main(["unstack", "4513", "4515"])
        self.assertEqual(rc, 0)
        mock_run.assert_called_once_with(
            [
                "gh",
                "api",
                "-H",
                "Accept: application/vnd.github+json",
                "-X",
                "POST",
                "repos/bazel-contrib/rules_python/stacks/4513/unstack",
                "-F=pull_requests[]=4515",
            ],
            capture_output=True,
            text=True,
            check=True,
        )

    @mock.patch.object(subprocess, "run", autospec=True)
    def test_show_formats_summary(self, mock_run: mock.MagicMock) -> None:
        mock_run.return_value = subprocess.CompletedProcess(
            args=[], returncode=0, stdout=_SAMPLE_STACK_JSON, stderr=""
        )
        data = gh_pr_stack.show_stack("bazel-contrib/rules_python", 4513)
        self.assertEqual(
            gh_pr_stack.format_stack(data),
            "stack #4513 base=main open=True\n"
            "  #4511 rickeylev/shrubbery/01-py-wheel-dist -> main draft=True state=open\n"
            "  #4512 rickeylev/shrubbery/02-py-console-script-gen -> rickeylev/shrubbery/01-py-wheel-dist draft=True state=open",
        )


if __name__ == "__main__":
    unittest.main()
