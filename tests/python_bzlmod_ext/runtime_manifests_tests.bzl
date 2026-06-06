"""Starlark unit tests for dynamic toolchain registration via manifests."""

load("@rules_testing//lib:analysis_test.bzl", "analysis_test")
load("@rules_testing//lib:test_suite.bzl", "test_suite")
load("@rules_testing//lib:util.bzl", rt_util = "util")
load("//python/private:python.bzl", "parse_modules")  # buildifier: disable=bzl-visibility
load("//python/private:repo_utils.bzl", "repo_utils")  # buildifier: disable=bzl-visibility
load("//tests/support/mocks:mocks.bzl", "mocks")  # buildifier: disable=bzl-visibility
load("//tests/support/mocks:python_ext.bzl", "python_ext")  # buildifier: disable=bzl-visibility

_tests = []

_mock_logger = repo_utils.logger(
    name = "mock",
    verbosity_level = "ERROR",
)

def _test_dynamic_manifest_toolchains(name):
    rt_util.helper_target(
        native.filegroup,
        name = name + "_subject",
    )
    analysis_test(
        name = name,
        target = name + "_subject",
        impl = _test_dynamic_manifest_toolchains_impl,
    )

def _test_dynamic_manifest_toolchains_impl(env, target):
    _ = target  # @unused

    # Construct Bzlmod mock module locally inside the test execution block.
    # We test using virtual patch version "3.11.99" (not present in TOOL_VERSIONS)
    # so that the populated config contains ONLY our dynamically parsed manifest keys
    # without any pre-populated multi-platform templates, allowing exact dictionary match!
    root_module = python_ext.module(
        name = "runtime_manifests",
        override = [
            python_ext.override(
                add_runtime_manifest_urls = [
                    "https://github.com/astral-sh/python-build-standalone/releases/download/20260414/SHA256SUMS",
                ],
                runtime_manifest_sha = "ce18fdfd47c66830a40ea9b9e314a14b1636bbfd684501bc5ca1fc6d55a7933f",
                register_all_versions = True,
            ),
        ],
        defaults = [
            python_ext.defaults(
                python_version = "3.11.99",
            ),
        ],
    )

    # Pre-populate mock_files directly to bypass download output struct key mismatch in mock read lookups.
    mock_mctx = mocks.mctx(
        modules = [root_module],
        mock_files = {
            "runtime_manifest": """
01e607cf764b97d4d5d6f69fd1ff3d8a9a162513dde5c39e98260fce40fe220a  cpython-3.11.99+20260414-x86_64-unknown-linux-gnu-pgo+lto-full.tar.zst
8b14030dd3af9ea7f7c51b4c90feb04afd8a8f45435727e67b875270bd08f3bc  cpython-3.11.99+20260414-x86_64-unknown-linux-gnu-install_only.tar.gz
""",
        },
    )

    res = parse_modules(
        module_ctx = mock_mctx,
        logger = _mock_logger,
    )

    tool_versions = res.config.default["tool_versions"]
    env.expect.that_bool("3.11.99" in tool_versions).equals(True)

    version_info = tool_versions["3.11.99"]

    # Assert on the entire dictionary at once!
    env.expect.that_dict(version_info).contains_exactly({
        "sha256": {
            "x86_64-unknown-linux-gnu": "8b14030dd3af9ea7f7c51b4c90feb04afd8a8f45435727e67b875270bd08f3bc",
        },
        "strip_prefix": {
            "x86_64-unknown-linux-gnu": "python",
        },
        "url": {
            "x86_64-unknown-linux-gnu": [
                "https://github.com/astral-sh/python-build-standalone/releases/download/20260414/cpython-3.11.99+20260414-x86_64-unknown-linux-gnu-install_only.tar.gz",
            ],
        },
    })

_tests.append(_test_dynamic_manifest_toolchains)

def _test_dynamic_manifest_files(name):
    rt_util.helper_target(
        native.filegroup,
        name = name + "_subject",
    )
    analysis_test(
        name = name,
        target = name + "_subject",
        impl = _test_dynamic_manifest_files_impl,
    )

def _test_dynamic_manifest_files_impl(env, target):
    _ = target  # @unused

    root_module = python_ext.module(
        name = "runtime_manifests",
        override = [
            python_ext.override(
                add_runtime_manifest_files = [
                    Label("//:SHA256SUMS"),
                ],
                base_url = "https://example.com/dl",
                register_all_versions = True,
            ),
        ],
        defaults = [
            python_ext.defaults(
                python_version = "3.12.99",
            ),
        ],
    )

    mock_mctx = mocks.mctx(
        modules = [root_module],
        mock_files = {
            str(Label("//:SHA256SUMS")): """
01e607cf764b97d4d5d6f69fd1ff3d8a9a162513dde5c39e98260fce40fe220a  cpython-3.12.99+20260414-x86_64-unknown-linux-gnu-pgo+lto-full.tar.zst
""",
        },
    )

    res = parse_modules(
        module_ctx = mock_mctx,
        logger = _mock_logger,
    )

    tool_versions = res.config.default["tool_versions"]
    env.expect.that_bool("3.12.99" in tool_versions).equals(True)

    version_info = tool_versions["3.12.99"]

    env.expect.that_dict(version_info).contains_exactly({
        "sha256": {
            "x86_64-unknown-linux-gnu": "01e607cf764b97d4d5d6f69fd1ff3d8a9a162513dde5c39e98260fce40fe220a",
        },
        "strip_prefix": {
            "x86_64-unknown-linux-gnu": "python/install",
        },
        "url": {
            "x86_64-unknown-linux-gnu": [
                "https://example.com/dl/cpython-3.12.99+20260414-x86_64-unknown-linux-gnu-pgo+lto-full.tar.zst",
            ],
        },
    })

_tests.append(_test_dynamic_manifest_files)

def runtime_manifests_test_suite(name):
    test_suite(
        name = name,
        tests = _tests,
    )
