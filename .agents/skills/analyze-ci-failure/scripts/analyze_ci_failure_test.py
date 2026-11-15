#!/usr/bin/env python3
"""Unit tests for analyze_ci_failure.py."""

import tempfile
import unittest
from pathlib import Path

import analyze_ci_failure

_FLAKE_BANNER = "Infrastructure / Flake Issue"
_CODE_BANNER = "Code / Configuration Issue"


class AnalyzeCiFailureTest(unittest.TestCase):
    def _classify_log(self, log_text: str) -> tuple[list[str], str]:
        with tempfile.TemporaryDirectory() as tmp_dir:
            log_path = Path(tmp_dir) / "ci.log"
            log_path.write_text(log_text, encoding="utf-8")
            errors = analyze_ci_failure.parse_log(str(log_path))
            plan = analyze_ci_failure.create_plan(
                "Default: Debian, Bazel 7.x", str(log_path), errors
            )
        return errors, plan

    def test_bazel_http_5xx_download_classified_as_flake_with_mirror_advice(
        self,
    ) -> None:
        errors, plan = self._classify_log(
            "INFO: Running Bazel...\n"
            "WARNING: Download from https://github.com/bazelbuild/rules_rust/releases/download/0.73.0/rules_rust-0.73.0.tar.gz failed: class java.io.IOException GET returned 500 Internal Server Error\n"
            "ERROR: Error in download_and_extract: java.io.IOException: Error downloading [https://github.com/bazelbuild/rules_rust/releases/download/0.73.0/rules_rust-0.73.0.tar.gz] to /tmp/r.tar.gz: GET returned 500 Internal Server Error\n"
        )
        self.assertEqual(len(errors), 2)
        self.assertIn(_FLAKE_BANNER, plan)
        self.assertIn("mirror.bazel.build", plan)

    def test_bazel_http_504_download_gets_mirror_advice_over_gateway_branch(
        self,
    ) -> None:
        _, plan = self._classify_log(
            "ERROR: Error in download_and_extract: java.io.IOException: Error downloading [https://example.com/tool.tar.gz] to /tmp/t.tar.gz: GET returned 504 Gateway Time-out\n"
        )
        self.assertIn(_FLAKE_BANNER, plan)
        self.assertIn("mirror.bazel.build", plan)

    def test_bazel_download_timeout_and_reset_classified_as_flake(self) -> None:
        for reason in (
            "Read timed out",
            "Connection reset",
            "Unexpected end of file from server",
        ):
            with self.subTest(reason=reason):
                _, plan = self._classify_log(
                    f"ERROR: java.io.IOException: Error downloading [https://example.com/a.tar.gz] to /tmp/a.tar.gz: {reason}\n"
                )
                self.assertIn(_FLAKE_BANNER, plan)

    def test_permanent_404_and_checksum_errors_not_classified_as_flake(self) -> None:
        for log_line in (
            "ERROR: java.io.IOException: Error downloading [https://example.com/missing.tar.gz] to /tmp/m.tar.gz: GET returned 404 Not Found\n",
            "ERROR: java.io.IOException: Error downloading [https://example.com/bad.tar.gz] to /tmp/b.tar.gz: Checksum was deadbeef but wanted cafebabe\n",
        ):
            with self.subTest(log_line=log_line):
                _, plan = self._classify_log(log_line)
                self.assertIn(_CODE_BANNER, plan)
                self.assertNotIn(_FLAKE_BANNER, plan)

    def test_benign_download_progress_lines_not_captured_by_parse_log(self) -> None:
        errors, _ = self._classify_log(
            "INFO: Download from https://example.com/ok.tar.gz succeeded\n"
            "ERROR: Analysis of target '//foo:bar' failed: build failed\n"
        )
        self.assertEqual(
            errors, ["ERROR: Analysis of target '//foo:bar' failed: build failed"]
        )

    def test_buildkite_apc_timestamp_prefix_stripped_from_errors(self) -> None:
        errors, _ = self._classify_log(
            "\x1b_bk;t=1794137028816\x07ERROR: Build did NOT complete successfully\n"
            "_bk;t=1794137028817 FAILED: Build did NOT complete successfully\n"
        )
        self.assertEqual(
            errors,
            [
                "ERROR: Build did NOT complete successfully",
                "FAILED: Build did NOT complete successfully",
            ],
        )

    def test_runner_dns_and_git_mirror_checkout_classified_as_flake(self) -> None:
        for log_text in (
            "fatal: unable to access 'https://github.com/bazel-contrib/rules_python.git/': Could not resolve host: github.com\n",
            "Error: getting/updating git mirror: exit status 128\n",
            "HTTPSConnectionPool(host='docs.python.org', port=443): Temporary failure in name resolution\n",
        ):
            with self.subTest(log_text=log_text):
                _, plan = self._classify_log(log_text)
                self.assertIn(_FLAKE_BANNER, plan)

    def test_windows_modextwd_cleanup_permission_denied_classified_as_flake(
        self,
    ) -> None:
        errors, plan = self._classify_log(
            "WARNING: errors encountered while analyzing target '//tests/py_zipapp:system_python_bin'\n"
            "Failed to clean up module context directory: C:/b/nzh6davs/modextwd/rules_rust++crate/cargo-bazel.exe (Permission denied)\n"
        )
        self.assertEqual(
            errors,
            [
                "Failed to clean up module context directory: C:/b/nzh6davs/modextwd/rules_rust++crate/cargo-bazel.exe (Permission denied)"
            ],
        )
        self.assertIn(_FLAKE_BANNER, plan)


if __name__ == "__main__":
    unittest.main()
