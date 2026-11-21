"""pytest_test rule implementation."""

load("//python:py_test.bzl", "py_test")

_DEFAULT_PYTEST = Label("//python/private/pytest_test:default_pytest")
_DEFAULT_PYTEST_BAZEL = Label("//python/private/pytest_test:default_pytest_bazel")

def pytest_test(
        *,
        name,
        srcs,
        pytest = None,
        pytest_bazel = None,
        pytest_shard = None,
        pytest_randomly = None,
        python_versions = None,
        **kwargs):
    """Run pytest tests.

    The tests are run with
    [pytest-bazel](https://pytest-bazel.readthedocs.io/latest/), which makes
    pytest follow the Bazel test encyclopedia, e.g. for `--test_filter`,
    sharding, `--runs_per_test` and the test outputs. See {doc}`/pytest` for
    setup and configuration.

    :::{versionadded} 2.5.0
    :::

    :::{versionchanged} VERSION_NEXT_FEATURE
    `pytest-randomly` and `pytest-shard` are no longer added by default, as
    `pytest-bazel` 1.0 shards the tests itself.
    :::

    Args:
        name: A unique name for this target.
        srcs: List of source files (test files). These are the files that
            pytest will run as tests.
        pytest: The pytest target to use. Defaults to `@pypi//pytest`.
        pytest_bazel: The pytest-bazel target to use (`pytest-bazel >= 1.0`).
            Defaults to `@pypi//pytest_bazel`.
        pytest_shard: Deprecated; `pytest-bazel >= 0.3.0` shards tests itself.
            If set and `shard_count` is specified, the target is added to
            `deps`.
        pytest_randomly: An optional pytest-randomly target, e.g.
            `@pypi//pytest_randomly`, to run the tests in a random order.
            `pytest-bazel` seeds it from `TEST_RANDOM_SEED` or the
            `--runs_per_test` run number. If set, the target is added to
            `deps`.
        python_versions: List of Python versions to test against. If specified,
            a test is created for each version and grouped under a test_suite
            named `name`.
        **kwargs: Additional arguments passed to {obj}`py_test`. Note that
            `main` is not a supported argument.
    """
    deps = kwargs.pop("deps", None) or []
    if pytest == None:
        pytest = _DEFAULT_PYTEST
    if pytest_bazel == None:
        pytest_bazel = _DEFAULT_PYTEST_BAZEL
    extra_deps = [pytest, pytest_bazel]
    if pytest_shard != None and kwargs.get("shard_count"):
        extra_deps.append(pytest_shard)
    if pytest_randomly != None and pytest_randomly not in extra_deps:
        extra_deps.append(pytest_randomly)
    kwargs["deps"] = deps + extra_deps

    if python_versions != None:
        _multi_pytest_test(
            name = name,
            srcs = srcs,
            python_versions = python_versions,
            **kwargs
        )
    else:
        _single_pytest_test(
            name = name,
            srcs = srcs,
            **kwargs
        )

def _multi_pytest_test(
        *,
        name,
        srcs,
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
        **kwargs):
    bootstrap_target = name + "_bootstrap"
    main_file = name + "_boot.py"
    _write_pytest_bootstrap(
        name = bootstrap_target,
        srcs = srcs,
        output_name = main_file,
        tags = ["manual"],
    )

    py_test(
        name = name,
        main = main_file,
        srcs = [bootstrap_target] + srcs,
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
            default = "//python/private/pytest_test:bootstrap_template",
            allow_single_file = True,
        ),
    },
)
