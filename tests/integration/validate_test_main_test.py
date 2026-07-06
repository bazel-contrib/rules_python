import unittest

from tests.integration import runner

_FLAG = "--@rules_python//python/config_settings:validate_test_main"


class ValidateTestMainTest(runner.TestCase):
    def test_inert_test_fails_when_enabled(self):
        """An inert test main should fail the build when validation is on."""
        result = self.run_bazel(
            "build",
            f"{_FLAG}=enabled",
            "//:inert_test",
            check=False,
        )
        self.assertNotEqual(result.exit_code, 0, "Expected build to fail")
        self.assert_result_matches(result, r"will not run any tests")

    def test_good_test_builds_when_enabled(self):
        """A main that invokes a runner should build when validation is on."""
        self.run_bazel("build", f"{_FLAG}=enabled", "//:good_test")

    def test_import_only_test_builds_when_enabled(self):
        """A main that only imports (defines nothing) is allowed when on."""
        self.run_bazel("build", f"{_FLAG}=enabled", "//:import_only_test")

    def test_inert_test_builds_when_disabled(self):
        """Validation is off by default, so even an inert test builds."""
        self.run_bazel("build", f"{_FLAG}=disabled", "//:inert_test")

    def test_inert_test_builds_by_default(self):
        """The default (auto) resolves to disabled, so an inert test builds."""
        self.run_bazel("build", "//:inert_test")


if __name__ == "__main__":
    # Enabling this makes the runner log subprocesses as the test goes along.
    # logging.basicConfig(level = "INFO")
    unittest.main()
