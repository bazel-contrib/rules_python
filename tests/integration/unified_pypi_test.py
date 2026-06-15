"""Integration test for Unified PyPI Hub dynamic dependency resolution."""

import unittest

from tests.integration import runner


class UnifiedPypiTest(runner.TestCase):
    def test_default_fallback_hub(self):
        self.run_bazel("test", "//:test_default")

    def test_transitioned_hub(self):
        self.run_bazel("test", "//:test_a")

    def test_cli_override(self):
        self.run_bazel(
            "run",
            "--@rules_python//python/config_settings:pypi_hub=pypi_a",
            "//:test_cli",
        )

    def test_disjoint_package_cquery_succeeds_but_build_fails(self):
        self.run_bazel("cquery", "//:bin_six_a")
        result = self.run_bazel("build", "//:bin_six_a", check=False)
        self.assertNotEqual(
            result.exit_code,
            0,
            "Expected build to fail during execution phase",
        )
        self.assert_result_matches(
            result,
            'ERROR: PyPI package "six" is not available when building under PyPI hub "pypi_a".',
        )

    def test_sibling_extra_alias_cquery_succeeds_but_build_fails(self):
        self.run_bazel("cquery", "//:bin_extra_b")
        result = self.run_bazel("build", "//:bin_extra_b", check=False)
        self.assertNotEqual(
            result.exit_code,
            0,
            "Expected build to fail during execution phase",
        )
        self.assert_result_matches(
            result,
            'ERROR: PyPI package "colorama:my_colorama" is not available when building under PyPI hub "pypi_b".',
        )


if __name__ == "__main__":
    unittest.main()
