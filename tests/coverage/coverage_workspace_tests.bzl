"""Tests for the wheel selection of the WORKSPACE coverage tool."""

load("@rules_testing//lib:test_suite.bzl", "test_suite")
load("//python/private/coverage:coverage_workspace.bzl", "select_wheels")  # buildifier: disable=bzl-visibility
load("//python/private/pypi:default_platforms.bzl", "default_platforms")  # buildifier: disable=bzl-visibility

_tests = []

_URL = "https://files.pythonhosted.org/packages/"

def _platforms(*names):
    platforms = default_platforms()
    return {name: platforms[name] for name in names}

def _wheel(filename, digest):
    return {"hash": "sha256:" + digest, "url": _URL + filename}

def _test_select_platform_specific_wheels(env):
    got = select_wheels(
        uv_lock = {"package": [
            {
                "name": "coverage",
                "source": {"registry": "https://pypi.org/simple"},
                "version": "7.0",
                "wheels": [
                    _wheel("coverage-7.0-cp313-cp313-manylinux_2_17_x86_64.whl", "deadb001"),
                    _wheel("coverage-7.0-cp313-cp313-macosx_11_0_arm64.whl", "deadb002"),
                    _wheel("coverage-7.0-py3-none-any.whl", "deadb003"),
                ],
            },
        ]},
        minor_mapping = {"3.13": "3.13.1"},
        platforms = _platforms("linux_s390x", "linux_x86_64", "osx_aarch64"),
    )

    # Each platform selects its own wheel and the platforms without a
    # platform specific wheel use the `none-any` wheel.
    env.expect.that_dict(got.tools).contains_exactly({
        "3.13": {
            "linux_s390x": "coverage_py3_none_any_deadb003",
            "linux_x86_64": "coverage_cp313_cp313_manylinux_2_17_x86_64_deadb001",
            "osx_aarch64": "coverage_cp313_cp313_macosx_11_0_arm64_deadb002",
        },
    })
    env.expect.that_dict(got.wheels["coverage_cp313_cp313_manylinux_2_17_x86_64_deadb001"]).contains_exactly({
        "filename": "coverage-7.0-cp313-cp313-manylinux_2_17_x86_64.whl",
        "integrity": "sha256-3q2wAQ==",
        "url": _URL + "coverage-7.0-cp313-cp313-manylinux_2_17_x86_64.whl",
    })
    env.expect.that_collection(got.wheels.keys()).contains_exactly([
        "coverage_cp313_cp313_macosx_11_0_arm64_deadb002",
        "coverage_cp313_cp313_manylinux_2_17_x86_64_deadb001",
        "coverage_py3_none_any_deadb003",
    ])

_tests.append(_test_select_platform_specific_wheels)

def _test_select_per_python_version(env):
    got = select_wheels(
        uv_lock = {"package": [
            {
                "name": "coverage",
                "resolution-markers": ["python_full_version < '3.10'"],
                "source": {"registry": "https://pypi.org/simple"},
                "version": "7.0",
                "wheels": [_wheel("coverage-7.0-py3-none-any.whl", "deadb001")],
            },
            {
                "name": "coverage",
                "resolution-markers": ["python_full_version >= '3.10'"],
                "source": {"registry": "https://pypi.org/simple"},
                "version": "8.0",
                "wheels": [_wheel("coverage-8.0-py3-none-any.whl", "deadb002")],
            },
        ]},
        minor_mapping = {"3.13": "3.13.1", "3.9": "3.9.1"},
        platforms = _platforms("linux_x86_64"),
    )

    # Newer coverage versions drop the support for older Python versions.
    env.expect.that_dict(got.tools).contains_exactly({
        "3.13": {"linux_x86_64": "coverage_py3_none_any_deadb002"},
        "3.9": {"linux_x86_64": "coverage_py3_none_any_deadb001"},
    })

_tests.append(_test_select_per_python_version)

def _test_select_skips_other_packages(env):
    got = select_wheels(
        uv_lock = {"package": [
            {
                "name": "other",
                "source": {"registry": "https://pypi.org/simple"},
                "version": "1.0",
                "wheels": [_wheel("other-1.0-py3-none-any.whl", "deadb001")],
            },
        ]},
        minor_mapping = {"3.13": "3.13.1"},
        platforms = _platforms("linux_x86_64"),
    )

    env.expect.that_dict(got.tools).contains_exactly({})
    env.expect.that_dict(got.wheels).contains_exactly({})

_tests.append(_test_select_skips_other_packages)

def coverage_workspace_test_suite(name):
    """Create the test suite.

    Args:
        name: the name of the test suite
    """
    test_suite(name = name, basic_tests = _tests)
