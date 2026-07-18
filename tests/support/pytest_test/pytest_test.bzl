"""pytest_test rule implementation."""

load("//python:py_test.bzl", "py_test")

_DEFAULT_PYTEST = Label("//tests/support/pytest_test:default_pytest")
_DEFAULT_PYTEST_BAZEL = Label("//tests/support/pytest_test:default_pytest_bazel")

def pytest_test(
        *,
        name,
        srcs,
        pytest = None,
        pytest_bazel = None,
        **kwargs):
    """Run pytest tests.

    Args:
        name: A unique name for this target.
        srcs: List of source files (test files). These are the files that
            pytest will run as tests.
        pytest: The pytest target to use. Defaults to @pypi//pytest.
        pytest_bazel: The pytest-bazel target to use. Defaults to
            @pypi//pytest_bazel.
        **kwargs: Additional arguments passed to py_test. Note that `main` is
            not a supported argument.
    """
    if pytest == None:
        pytest = _DEFAULT_PYTEST
    if pytest_bazel == None:
        pytest_bazel = _DEFAULT_PYTEST_BAZEL

    bootstrap_target = name + "_bootstrap"
    main_file = name + "_boot.py"
    _write_pytest_bootstrap(
        name = bootstrap_target,
        srcs = srcs,
        output_name = main_file,
    )

    py_test(
        name = name,
        main = main_file,
        srcs = [bootstrap_target] + srcs,
        deps = kwargs.pop("deps", []) + [
            pytest,
            pytest_bazel,
        ],
        **kwargs
    )

def _write_pytest_bootstrap_impl(ctx):
    output = ctx.actions.declare_file(ctx.attr.output_name)
    test_files = "\n".join([f.short_path for f in ctx.files.srcs])

    ctx.actions.expand_template(
        output = output,
        template = ctx.file._bootstrap_template,
        substitutions = {
            "%TEST_FILES%": test_files,
        },
    )
    return [DefaultInfo(files = depset([output]))]

_write_pytest_bootstrap = rule(
    implementation = _write_pytest_bootstrap_impl,
    attrs = {
        "output_name": attr.string(mandatory = True),
        "srcs": attr.label_list(allow_files = True),
        "_bootstrap_template": attr.label(
            default = "//tests/support/pytest_test:bootstrap_template",
            allow_single_file = True,
        ),
    },
)
