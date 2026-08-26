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
        python_versions = None,
        **kwargs):
    """Run pytest tests.

    Args:
        name: A unique name for this target.
        srcs: List of source files (test files). These are the files that
            pytest will run as tests.
        pytest: The pytest target to use. Defaults to @pypi//pytest.
        pytest_bazel: The pytest-bazel target to use. Defaults to
            @pypi//pytest_bazel.
        python_versions: List of Python versions to test against. If specified,
            a test is created for each version and grouped under a test_suite
            named `name`.
        **kwargs: Additional arguments passed to py_test. Note that `main` is
            not a supported argument.
    """
    if python_versions != None:
        _multi_pytest_test(
            name = name,
            srcs = srcs,
            pytest = pytest,
            pytest_bazel = pytest_bazel,
            python_versions = python_versions,
            **kwargs
        )
    else:
        _single_pytest_test(
            name = name,
            srcs = srcs,
            pytest = pytest,
            pytest_bazel = pytest_bazel,
            **kwargs
        )

def _multi_pytest_test(
        *,
        name,
        srcs,
        pytest = None,
        pytest_bazel = None,
        python_versions,
        **kwargs):
    if "python_version" in kwargs:
        fail(
            "Cannot specify both python_version and python_versions in " +
            "pytest_test; use one or the other.",
        )
    if not python_versions:
        fail("python_versions must not be empty for {}".format(name))

    tests = []
    for python_version in python_versions:
        test_name = _get_version_test_name(name, python_version)
        _single_pytest_test(
            name = test_name,
            srcs = srcs,
            pytest = pytest,
            pytest_bazel = pytest_bazel,
            python_version = python_version,
            **kwargs
        )
        tests.append(":" + test_name)

    test_suite_kwargs = {}
    if "visibility" in kwargs:
        test_suite_kwargs["visibility"] = kwargs["visibility"]

    native.test_suite(
        name = name,
        tests = tests,
        **test_suite_kwargs
    )

def _single_pytest_test(
        *,
        name,
        srcs,
        pytest = None,
        pytest_bazel = None,
        **kwargs):
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

    kwargs = dict(kwargs)
    deps = kwargs.pop("deps", [])
    py_test(
        name = name,
        main = main_file,
        srcs = [bootstrap_target] + srcs,
        deps = deps + [
            pytest,
            pytest_bazel,
        ],
        **kwargs
    )

def _get_version_test_name(name, python_version):
    version_str = str(python_version)
    if not version_str.startswith("py"):
        version_str = "py" + version_str

    if name.endswith("_test"):
        return "{}_{}_test".format(name[:-len("_test")], version_str)
    elif name.endswith("_tests"):
        return "{}_{}_tests".format(name[:-len("_tests")], version_str)
    return "{}_{}".format(name, version_str)

get_version_test_name = _get_version_test_name

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
