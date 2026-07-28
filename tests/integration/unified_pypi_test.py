"""Integration test for Unified PyPI Hub dynamic dependency resolution."""

import contextlib
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
            "--@rules_python//python/config_settings:venv=pypi_a",
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
            'ERROR: PyPI package "six" is not available when building under PyPI hub "pypi_a"\\. Try adding it to the requirements of this hub',
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
            'ERROR: PyPI package "colorama:my_colorama" is not available when building under PyPI hub "pypi_b"\\. Try adding it to the requirements of this hub',
        )

    @contextlib.contextmanager
    def _temp_modify_file(self, path, new_content):
        original_content = path.read_text()
        path.write_text(new_content)
        try:
            yield
        finally:
            path.write_text(original_content)

    def test_invalid_default_hub_fails_evaluation(self):
        module_bazel = self.repo_root / "MODULE.bazel"
        invalid_content = module_bazel.read_text().replace(
            'pip.default(default_hub = "pypi_b")',
            'pip.default(default_hub = "invalid_hub")',
        )
        with self._temp_modify_file(module_bazel, invalid_content):
            # Run bazel cquery and expect it to fail during loading/extension phase
            result = self.run_bazel("cquery", "//:test_default", check=False)
            self.assertNotEqual(
                result.exit_code,
                0,
                "Expected extension evaluation to fail due to invalid default_hub",
            )
            self.assert_result_matches(
                result,
                "default_hub 'invalid_hub' is not a defined PyPI hub",
            )

    def test_unimplemented_declared_dep_fails_build(self):
        # Even though cquery succeeds:
        self.run_bazel("cquery", "//:bin_declared_only")

        # Build must fail because the package is not implemented by any concrete hub
        result = self.run_bazel("build", "//:bin_declared_only", check=False)
        self.assertNotEqual(result.exit_code, 0)
        self.assert_result_matches(
            result,
            'ERROR: PyPI package "declared_only_pkg" is not available when building under PyPI hub "pypi_b"\\. Try adding it to the requirements of this hub',
        )

    def test_unimplemented_declared_dep_alias_fails_build(self):
        # Build must fail for alias too
        result = self.run_bazel("build", "//:bin_declared_only_alias", check=False)
        self.assertNotEqual(result.exit_code, 0)
        self.assert_result_matches(
            result,
            'ERROR: PyPI package "declared_only_pkg:declared-only-alias" is not available when building under PyPI hub "pypi_b"\\. Try adding it to the requirements of this hub',
        )


if __name__ == "__main__":
    unittest.main()
