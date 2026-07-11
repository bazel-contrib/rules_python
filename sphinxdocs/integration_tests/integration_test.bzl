"""Helpers for running bazel-in-bazel integration tests for sphinxdocs."""

load(
    "@rules_bazel_integration_test//bazel_integration_test:defs.bzl",
    "bazel_integration_test",
    "integration_test_utils",
)
load("@rules_python//python:py_test.bzl", "py_test")

def _test_runner(*, name, bazel_version, py_main, py_deps):
    test_runner = "{}_bazel_{}_py_runner".format(name, bazel_version)
    py_test(
        name = test_runner,
        srcs = [py_main],
        main = py_main,
        deps = ["//integration_tests:runner_lib"] + py_deps,
        tags = ["manual"],
    )
    return test_runner

def sphinxdocs_integration_test(
        name,
        workspace_path = "workspace",
        tags = None,
        py_main = None,
        py_deps = None,
        bazel_versions = None,
        **kwargs):
    """Runs a bazel-in-bazel integration test for sphinxdocs.

    Args:
        name: Name of the test.
        workspace_path: The directory name of the sub-workspace.
        tags: Test tags.
        py_main: Main Python test runner script.
        py_deps: Dependencies for py_main.
        bazel_versions: List of bazel versions to test.
        **kwargs: Passed to bazel_integration_test.
    """
    workspace_files = integration_test_utils.glob_workspace_files(workspace_path)
    native.filegroup(
        name = name + "_workspace_files",
        srcs = workspace_files + [
            "//:distribution",
        ],
    )
    kwargs.setdefault("size", "large")
    for bazel_version in bazel_versions or ["self"]:
        test_runner = _test_runner(
            name = name,
            bazel_version = bazel_version,
            py_main = py_main,
            py_deps = py_deps or [],
        )
        bazel_integration_test(
            name = "{}_bazel_{}".format(name, bazel_version),
            workspace_path = workspace_path,
            test_runner = test_runner,
            bazel_version = bazel_version,
            workspace_files = [name + "_workspace_files"],
            tags = (tags or []) + [
                "exclusive",
                "no-sandbox",
                "no-remote-exec",
                "integration-test",
            ],
            **kwargs
        )
