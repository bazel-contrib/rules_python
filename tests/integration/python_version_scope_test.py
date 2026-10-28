"""Test the consumer opt-in, including baseline reset and exec propagation."""

import unittest

from tests.integration import runner


class PythonVersionScopeTest(runner.TestCase):
    def test_project_scope(self):
        self.run_bazel(
            "build",
            "--@rules_python//python/config_settings:python_version=3.10",
            "//bindings:check311",
            "//bindings:check312",
        )

        result = self.run_bazel(
            "cquery",
            "--@rules_python//python/config_settings:python_version=3.10",
            'filter("native:core", deps(set(//bindings:check311 //bindings:check312)))',
            "--output=label",
        )
        self.assertEqual(len(result.stdout.strip().splitlines()), 1)

    def test_default_scope(self):
        module = self.repo_root / "MODULE.bazel"
        bindings = self.repo_root / "bindings/BUILD.bazel"
        project = self.repo_root / "PROJECT.scl"
        original_project = project.read_text()
        original_module = module.read_text()
        original_bindings = bindings.read_text()
        try:
            project.unlink()
            module.write_text(
                original_module.replace(
                    'config.python_version_scope(scope = "project")', ""
                )
            )
            bindings.write_text(
                original_bindings.replace(
                    'native_version = "3.10"', 'native_version = "inherit"'
                )
            )
            # Building the flag's own package must not need a root PROJECT.scl.
            self.run_bazel(
                "build",
                "--@rules_python//python/config_settings:python_version=3.10",
                "//bindings:check311",
                "//bindings:check312",
                "@rules_python//python/config_settings:python_version",
            )
        finally:
            module.write_text(original_module)
            bindings.write_text(original_bindings)
            project.write_text(original_project)

    def test_dependency_cannot_configure_scope(self):
        module = self.repo_root / "MODULE.bazel"
        bindings = self.repo_root / "bindings/BUILD.bazel"
        original = module.read_text()
        original_bindings = bindings.read_text()
        dependency = self.repo_root / "dependency"
        dependency.mkdir()
        (dependency / "MODULE.bazel").write_text(
            'module(name = "dependency")\n'
            'bazel_dep(name = "rules_python", version = "0.0.0")\n'
            'config = use_extension("@rules_python//python/extensions:config.bzl", "config")\n'
            'config.python_version_scope(scope = "project")\n'
        )
        try:
            module.write_text(
                original.replace('config.python_version_scope(scope = "project")', "")
                + '\nbazel_dep(name = "dependency")\n'
                'local_path_override(module_name = "dependency", path = "dependency")\n'
            )
            bindings.write_text(
                original_bindings.replace(
                    'native_version = "3.10"', 'native_version = "inherit"'
                )
            )
            self.run_bazel(
                "build",
                "--@rules_python//python/config_settings:python_version=3.10",
                "//bindings:check311",
                "//bindings:check312",
            )
        finally:
            module.write_text(original)
            bindings.write_text(original_bindings)
            (dependency / "MODULE.bazel").unlink()
            dependency.rmdir()

    def test_duplicate_configuration(self):
        module = self.repo_root / "MODULE.bazel"
        original = module.read_text()
        try:
            module.write_text(
                original + '\nconfig.python_version_scope(scope = "project")\n'
            )
            result = self.run_bazel("build", "//bindings:check311", check=False)
            self.assertNotEqual(result.exit_code, 0)
            self.assert_result_matches(
                result, "python_version_scope may only be configured once"
            )
        finally:
            module.write_text(original)


if __name__ == "__main__":
    unittest.main()
