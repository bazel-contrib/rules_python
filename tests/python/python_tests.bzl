# Copyright 2024 The Bazel Authors. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

"""Unit tests for //python/extensions:python.bzl bzlmod extension."""

load("@pythons_hub//:versions.bzl", "MINOR_MAPPING")
load("@rules_testing//lib:test_suite.bzl", "test_suite")
load("//python/private:bzlmod_enabled.bzl", "BZLMOD_ENABLED")  # buildifier: disable=bzl-visibility
load("//python/private:python.bzl", "parse_modules")  # buildifier: disable=bzl-visibility
load("//python/private:repo_utils.bzl", "repo_utils")  # buildifier: disable=bzl-visibility
load("//tests/support/mocks:python_ext.bzl", "python_ext")

_tests = []

def _rules_python_module(is_root = False):
    """A mock of what the real rules_python MODULE.bazel looks like."""
    return python_ext.module(
        name = "rules_python",
        defaults = [python_ext.defaults(python_version = "3.11")],
        toolchain = [python_ext.toolchain(python_version = "3.11")],
        is_root = is_root,
    )

def _test_default_from_rules_python_when_rules_python_is_root(env):
    """Verify that rules_python (as root module) default is applied."""
    py = parse_modules(
        module_ctx = python_ext.mctx(
            _rules_python_module(is_root = True),
        ),
        logger = repo_utils.logger(verbosity_level = 0, name = "python"),
    )

    # The value there should be consistent in bzlmod with the automatically
    # calculated value Please update the MINOR_MAPPING in //python:versions.bzl
    # when this part starts failing.
    env.expect.that_dict(py.config.minor_mapping).contains_exactly(MINOR_MAPPING)
    env.expect.that_collection(py.config.kwargs).has_size(0)
    env.expect.that_collection(py.config.default.keys()).contains_exactly([
        "base_urls",
        "tool_versions",
        "platforms",
    ])
    env.expect.that_str(py.default_python_version).equals("3.11")

    want_toolchain = struct(
        name = "python_3_11",
        python_version = "3.11",
        register_coverage_tool = False,
    )
    env.expect.that_collection(py.toolchains).contains_exactly([want_toolchain])

_tests.append(_test_default_from_rules_python_when_rules_python_is_root)

def _test_default_from_rules_python_when_rules_python_is_not_root(env):
    """Verify that rules_python default applies when rules_python is not the root module."""
    py = parse_modules(
        module_ctx = python_ext.mctx(
            _rules_python_module(),
        ),
        logger = repo_utils.logger(verbosity_level = 0, name = "python"),
    )

    env.expect.that_str(py.default_python_version).equals("3.11")

    want_toolchain = struct(
        name = "python_3_11",
        python_version = "3.11",
        register_coverage_tool = False,
    )
    env.expect.that_collection(py.toolchains).contains_exactly([want_toolchain])

_tests.append(_test_default_from_rules_python_when_rules_python_is_not_root)

def _test_default_with_patch_version(env):
    py = parse_modules(
        module_ctx = python_ext.mctx(
            modules = [
                python_ext.module(
                    name = "alpha",
                    is_root = True,
                    toolchain = [python_ext.toolchain(python_version = "3.11.2")],
                ),
                _rules_python_module(is_root = False),
            ],
        ),
        logger = repo_utils.logger(verbosity_level = 0, name = "python"),
    )

    env.expect.that_str(py.default_python_version).equals("3.11.2")

    want_toolchain = struct(
        name = "python_3_11_2",
        python_version = "3.11.2",
        register_coverage_tool = False,
    )
    env.expect.that_collection(py.toolchains).contains_at_least([want_toolchain])

_tests.append(_test_default_with_patch_version)

def _test_toolchain_ordering(env):
    py = parse_modules(
        module_ctx = python_ext.mctx(
            python_ext.module(
                name = "my_module",
                is_root = True,
                toolchain = [
                    python_ext.toolchain(python_version = "3.10"),
                    python_ext.toolchain(python_version = "3.10.15"),
                    python_ext.toolchain(python_version = MINOR_MAPPING["3.10"]),
                    python_ext.toolchain(python_version = "3.10.13"),
                    python_ext.toolchain(python_version = "3.11.1"),
                    python_ext.toolchain(python_version = "3.11.10"),
                    python_ext.toolchain(
                        python_version = MINOR_MAPPING["3.11"],
                        is_default = True,
                    ),
                ],
            ),
            _rules_python_module(),
        ),
        logger = repo_utils.logger(verbosity_level = 0, name = "python"),
    )
    got_versions = [
        t.python_version
        for t in py.toolchains
    ]

    env.expect.that_str(py.default_python_version).equals(MINOR_MAPPING["3.11"])
    env.expect.that_dict(py.config.minor_mapping).contains_exactly(MINOR_MAPPING)
    env.expect.that_collection(got_versions).contains_exactly([
        # First the full-version toolchains that are in minor_mapping
        # so that they get matched first if only the `python_version` is in MINOR_MAPPING
        #
        # The default version is always set in the `python_version` flag, so know, that
        # the default match will be somewhere in the first bunch.
        "3.10",
        MINOR_MAPPING["3.10"],
        "3.11",
        MINOR_MAPPING["3.11"],
        # Next, the rest, where we will match things based on the `python_version` being
        # the same
        "3.10.15",
        "3.10.13",
        "3.11.1",
        "3.11.10",
    ]).in_order()

_tests.append(_test_toolchain_ordering)

def _test_default_from_defaults(env):
    py = parse_modules(
        module_ctx = python_ext.mctx(
            python_ext.module(
                name = "my_root_module",
                defaults = [python_ext.defaults(python_version = "3.11")],
                is_root = True,
                toolchain = [
                    python_ext.toolchain(python_version = "3.10"),
                    python_ext.toolchain(python_version = "3.11"),
                    python_ext.toolchain(python_version = "3.12"),
                ],
            ),
        ),
        logger = repo_utils.logger(verbosity_level = 0, name = "python"),
    )

    env.expect.that_str(py.default_python_version).equals("3.11")

    want_toolchains = [
        struct(
            name = "python_3_" + minor_version,
            python_version = "3." + minor_version,
            register_coverage_tool = False,
        )
        for minor_version in ["10", "11", "12"]
    ]
    env.expect.that_collection(py.toolchains).contains_exactly(want_toolchains)

_tests.append(_test_default_from_defaults)

def _test_default_from_defaults_env(env):
    py = parse_modules(
        module_ctx = python_ext.mctx(
            python_ext.module(
                name = "my_root_module",
                defaults = [
                    python_ext.defaults(
                        python_version = "3.11",
                        python_version_env = "PYENV_VERSION",
                    ),
                ],
                is_root = True,
                toolchain = [
                    python_ext.toolchain(python_version = "3.10"),
                    python_ext.toolchain(python_version = "3.11"),
                    python_ext.toolchain(python_version = "3.12"),
                ],
            ),
            environ = {"PYENV_VERSION": "3.12"},
        ),
        logger = repo_utils.logger(verbosity_level = 0, name = "python"),
    )

    env.expect.that_str(py.default_python_version).equals("3.12")

    want_toolchains = [
        struct(
            name = "python_3_" + minor_version,
            python_version = "3." + minor_version,
            register_coverage_tool = False,
        )
        for minor_version in ["10", "11", "12"]
    ]
    env.expect.that_collection(py.toolchains).contains_exactly(want_toolchains)

_tests.append(_test_default_from_defaults_env)

def _test_default_from_defaults_file(env):
    py = parse_modules(
        module_ctx = python_ext.mctx(
            python_ext.module(
                name = "my_root_module",
                defaults = [
                    python_ext.defaults(
                        python_version_file = "@@//:.python-version",
                    ),
                ],
                is_root = True,
                toolchain = [
                    python_ext.toolchain(python_version = "3.10"),
                    python_ext.toolchain(python_version = "3.11"),
                    python_ext.toolchain(python_version = "3.12"),
                ],
            ),
            mock_files = {"@@//:.python-version": "3.12\n"},
        ),
        logger = repo_utils.logger(verbosity_level = 0, name = "python"),
    )

    env.expect.that_str(py.default_python_version).equals("3.12")

    want_toolchains = [
        struct(
            name = "python_3_" + minor_version,
            python_version = "3." + minor_version,
            register_coverage_tool = False,
        )
        for minor_version in ["10", "11", "12"]
    ]
    env.expect.that_collection(py.toolchains).contains_exactly(want_toolchains)

_tests.append(_test_default_from_defaults_file)

def _test_default_from_single_toolchain(env):
    py = parse_modules(
        module_ctx = python_ext.mctx(
            python_ext.module(
                name = "my_root_module",
                is_root = True,
                toolchain = [python_ext.toolchain(python_version = "3.12")],
            ),
            _rules_python_module(),
        ),
        logger = repo_utils.logger(verbosity_level = 0, name = "python"),
    )
    env.expect.that_str(py.default_python_version).equals("3.12")

_tests.append(_test_default_from_single_toolchain)

def _test_defaults_overrides_single_toolchain(env):
    py = parse_modules(
        module_ctx = python_ext.mctx(
            python_ext.module(
                name = "my_root_module",
                defaults = [
                    # This relies on rules_python registering 3.11
                    python_ext.defaults(python_version = "3.11"),
                ],
                is_root = True,
                toolchain = [python_ext.toolchain(python_version = "3.12")],
            ),
            _rules_python_module(),
        ),
        logger = repo_utils.logger(verbosity_level = 0, name = "python"),
    )
    env.expect.that_str(py.default_python_version).equals("3.11")

_tests.append(_test_defaults_overrides_single_toolchain)

def _test_defaults_overrides_toolchains_setting_is_default(env):
    py = parse_modules(
        module_ctx = python_ext.mctx(
            python_ext.module(
                name = "my_root_module",
                defaults = [python_ext.defaults(python_version = "3.13")],
                is_root = True,
                toolchain = [
                    python_ext.toolchain(python_version = "3.13"),
                    python_ext.toolchain(
                        python_version = "3.12",
                        is_default = True,
                    ),
                ],
            ),
            _rules_python_module(),
        ),
        logger = repo_utils.logger(verbosity_level = 0, name = "python"),
    )
    env.expect.that_str(py.default_python_version).equals("3.13")

_tests.append(_test_defaults_overrides_toolchains_setting_is_default)

def _test_first_occurance_of_the_toolchain_wins(env):
    py = parse_modules(
        module_ctx = python_ext.mctx(
            modules = [
                python_ext.module(
                    name = "my_module",
                    is_root = True,
                    toolchain = [python_ext.toolchain(python_version = "3.12")],
                ),
                python_ext.module(
                    name = "some_module",
                    is_root = False,
                    toolchain = [
                        python_ext.toolchain(
                            python_version = "3.12",
                            configure_coverage_tool = True,
                        ),
                    ],
                ),
                _rules_python_module(),
            ],
            environ = {
                "RULES_PYTHON_BZLMOD_DEBUG": "1",
            },
        ),
        logger = repo_utils.logger(verbosity_level = 0, name = "python"),
    )

    env.expect.that_str(py.default_python_version).equals("3.12")

    my_module_toolchain = struct(
        name = "python_3_12",
        python_version = "3.12",
        # NOTE: coverage stays disabled even though `some_module` was
        # configuring something else.
        register_coverage_tool = False,
    )
    rules_python_toolchain = struct(
        name = "python_3_11",
        python_version = "3.11",
        register_coverage_tool = False,
    )
    env.expect.that_collection(py.toolchains).contains_exactly([
        rules_python_toolchain,
        my_module_toolchain,  # default toolchain is last
    ]).in_order()

    env.expect.that_dict(py.debug_info).contains_exactly({
        "toolchains_registered": [
            {"module": {"is_root": True, "name": "my_module"}, "name": "python_3_12"},
            {"module": {"is_root": False, "name": "rules_python"}, "name": "python_3_11"},
        ],
    })

_tests.append(_test_first_occurance_of_the_toolchain_wins)

def _test_auth_overrides(env):
    py = parse_modules(
        module_ctx = python_ext.mctx(
            python_ext.module(
                name = "my_module",
                is_root = True,
                override = [
                    python_ext.override(
                        auth_patterns = {"foo": "bar"},
                        netrc = "/my/netrc",
                    ),
                ],
                toolchain = [python_ext.toolchain(python_version = "3.12")],
            ),
            _rules_python_module(),
        ),
        logger = repo_utils.logger(verbosity_level = 0, name = "python"),
    )

    env.expect.that_dict(py.config.default).contains_at_least({
        "auth_patterns": {"foo": "bar"},
        "netrc": "/my/netrc",
    })
    env.expect.that_str(py.default_python_version).equals("3.12")

    my_module_toolchain = struct(
        name = "python_3_12",
        python_version = "3.12",
        register_coverage_tool = False,
    )
    rules_python_toolchain = struct(
        name = "python_3_11",
        python_version = "3.11",
        register_coverage_tool = False,
    )
    env.expect.that_collection(py.toolchains).contains_exactly([
        rules_python_toolchain,
        my_module_toolchain,
    ]).in_order()

_tests.append(_test_auth_overrides)

def _test_add_target_settings(env):
    py = parse_modules(
        module_ctx = python_ext.mctx(
            python_ext.module(
                name = "my_module",
                is_root = True,
                override = [
                    python_ext.override(
                        add_target_settings = [
                            "@@//my:custom_setting",
                        ],
                    ),
                ],
                toolchain = [python_ext.toolchain(python_version = "3.12")],
            ),
            _rules_python_module(),
        ),
        logger = repo_utils.logger(verbosity_level = 0, name = "python"),
    )

    env.expect.that_collection(
        py.config.add_target_settings,
    ).contains_exactly(["@@//my:custom_setting"])

_tests.append(_test_add_target_settings)

def _test_add_new_version(env):
    py = parse_modules(
        module_ctx = python_ext.mctx(
            python_ext.module(
                name = "my_module",
                is_root = True,
                override = [
                    python_ext.override(
                        available_python_versions = [
                            "3.12.4",
                            "3.13.0",
                            "3.13.1",
                            "3.13.99",
                        ],
                        base_urls = [],
                        minor_mapping = {
                            "3.13": "3.13.99",
                        },
                    ),
                ],
                single_version_override = [
                    python_ext.single_version_override(
                        distutils = None,
                        distutils_content = "",
                        patch_strip = 0,
                        patches = [],
                        python_version = "3.13.0",
                        sha256 = {
                            "aarch64-unknown-linux-gnu": "deadbeef",
                        },
                        strip_prefix = "prefix",
                        urls = ["example.org"],
                    ),
                ],
                single_version_platform_override = [
                    python_ext.single_version_platform_override(
                        coverage_tool = "specific_cov_tool",
                        patch_strip = 2,
                        patches = ["specific-patch.txt"],
                        platform = "aarch64-unknown-linux-gnu",
                        python_version = "3.13.99",
                        sha256 = "deadb00f",
                        strip_prefix = "python",
                        urls = ["something.org", "else.org"],
                    ),
                ],
                toolchain = [python_ext.toolchain(python_version = "3.13")],
            ),
        ),
        logger = repo_utils.logger(verbosity_level = 0, name = "python"),
    )

    env.expect.that_str(py.default_python_version).equals("3.13")
    env.expect.that_collection(py.config.default["tool_versions"].keys()).contains_exactly([
        "3.12.4",
        "3.13.0",
        "3.13.1",
        "3.13.99",
    ])
    env.expect.that_dict(py.config.default["tool_versions"]["3.13.0"]).contains_exactly({
        "sha256": {"aarch64-unknown-linux-gnu": "deadbeef"},
        "strip_prefix": {"aarch64-unknown-linux-gnu": "prefix"},
        "url": {"aarch64-unknown-linux-gnu": ["example.org"]},
    })
    env.expect.that_dict(py.config.default["tool_versions"]["3.13.99"]).contains_exactly({
        "coverage_tool": {"aarch64-unknown-linux-gnu": "specific_cov_tool"},
        "patch_strip": {"aarch64-unknown-linux-gnu": 2},
        "patches": {"aarch64-unknown-linux-gnu": ["specific-patch.txt"]},
        "sha256": {"aarch64-unknown-linux-gnu": "deadb00f"},
        "strip_prefix": {"aarch64-unknown-linux-gnu": "python"},
        "url": {"aarch64-unknown-linux-gnu": ["something.org", "else.org"]},
    })
    env.expect.that_dict(py.config.minor_mapping).contains_exactly({
        "3.12": "3.12.4",  # The `minor_mapping` will be overriden only for the missing keys
        "3.13": "3.13.99",
    })
    env.expect.that_collection(py.toolchains).contains_exactly([
        struct(
            name = "python_3_13",
            python_version = "3.13",
            register_coverage_tool = False,
        ),
    ])

_tests.append(_test_add_new_version)

def _test_register_all_versions(env):
    py = parse_modules(
        module_ctx = python_ext.mctx(
            python_ext.module(
                name = "my_module",
                is_root = True,
                override = [
                    python_ext.override(
                        available_python_versions = [
                            "3.12.4",
                            "3.13.0",
                            "3.13.1",
                            "3.13.99",
                        ],
                        base_urls = [],
                        register_all_versions = True,
                    ),
                ],
                single_version_override = [
                    python_ext.single_version_override(
                        python_version = "3.13.0",
                        sha256 = {
                            "aarch64-unknown-linux-gnu": "deadbeef",
                        },
                        urls = ["example.org"],
                    ),
                ],
                single_version_platform_override = [
                    python_ext.single_version_platform_override(
                        platform = "aarch64-unknown-linux-gnu",
                        python_version = "3.13.99",
                        sha256 = "deadb00f",
                        urls = ["something.org"],
                    ),
                ],
                toolchain = [python_ext.toolchain(python_version = "3.13")],
            ),
        ),
        logger = repo_utils.logger(verbosity_level = 0, name = "python"),
    )

    env.expect.that_str(py.default_python_version).equals("3.13")
    env.expect.that_collection(py.config.default["tool_versions"].keys()).contains_exactly([
        "3.12.4",
        "3.13.0",
        "3.13.1",
        "3.13.99",
    ])
    env.expect.that_dict(py.config.minor_mapping).contains_exactly({
        # The mapping is calculated automatically
        "3.12": "3.12.4",
        "3.13": "3.13.99",
    })
    env.expect.that_collection(py.toolchains).contains_exactly([
        struct(
            name = name,
            python_version = version,
            register_coverage_tool = False,
        )
        for name, version in {
            "python_3_12": "3.12",
            "python_3_12_4": "3.12.4",
            "python_3_13": "3.13",
            "python_3_13_0": "3.13.0",
            "python_3_13_1": "3.13.1",
            "python_3_13_99": "3.13.99",
        }.items()
    ])

_tests.append(_test_register_all_versions)

def _test_ignore_unsupported_versions(env):
    py = parse_modules(
        module_ctx = python_ext.mctx(
            python_ext.module(
                name = "my_module",
                is_root = True,
                override = [
                    python_ext.override(
                        available_python_versions = [
                            "3.12.4",
                            "3.13.0",
                            "3.13.1",
                        ],
                        base_urls = [],
                        minor_mapping = {
                            "3.12": "3.12.4",
                            "3.13": "3.13.1",
                        },
                    ),
                ],
                single_version_override = [
                    python_ext.single_version_override(
                        python_version = "3.13.0",
                        sha256 = {
                            "aarch64-unknown-linux-gnu": "deadbeef",
                        },
                        urls = ["example.org"],
                    ),
                ],
                single_version_platform_override = [
                    python_ext.single_version_platform_override(
                        platform = "aarch64-unknown-linux-gnu",
                        python_version = "3.13.99",
                        sha256 = "deadb00f",
                        urls = ["something.org"],
                    ),
                ],
                toolchain = [
                    python_ext.toolchain(python_version = "3.11"),
                    python_ext.toolchain(python_version = "3.12"),
                    python_ext.toolchain(
                        python_version = "3.13",
                        is_default = True,
                    ),
                ],
            ),
        ),
        logger = repo_utils.logger(verbosity_level = 0, name = "python"),
    )

    env.expect.that_str(py.default_python_version).equals("3.13")
    env.expect.that_collection(py.config.default["tool_versions"].keys()).contains_exactly([
        "3.12.4",
        "3.13.0",
        "3.13.1",
    ])
    env.expect.that_dict(py.config.minor_mapping).contains_exactly({
        # The mapping is calculated automatically
        "3.12": "3.12.4",
        "3.13": "3.13.1",
    })
    env.expect.that_collection(py.toolchains).contains_exactly([
        struct(
            name = name,
            python_version = version,
            register_coverage_tool = False,
        )
        for name, version in {
            # NOTE: that '3.11' wont be actually registered and present in the
            # `tool_versions` above.
            "python_3_11": "3.11",
            "python_3_12": "3.12",
            "python_3_13": "3.13",
        }.items()
    ])

_tests.append(_test_ignore_unsupported_versions)

def _test_add_patches(env):
    py = parse_modules(
        module_ctx = python_ext.mctx(
            python_ext.module(
                name = "my_module",
                is_root = True,
                override = [
                    python_ext.override(
                        available_python_versions = ["3.13.0"],
                        base_urls = [],
                        minor_mapping = {
                            "3.13": "3.13.0",
                        },
                    ),
                ],
                single_version_override = [
                    python_ext.single_version_override(
                        distutils = None,
                        distutils_content = "",
                        patch_strip = 1,
                        patches = ["common.txt"],
                        python_version = "3.13.0",
                        sha256 = {
                            "aarch64-apple-darwin": "deadbeef",
                            "aarch64-unknown-linux-gnu": "deadbeef",
                        },
                        strip_prefix = "prefix",
                        urls = ["example.org"],
                    ),
                ],
                single_version_platform_override = [
                    python_ext.single_version_platform_override(
                        coverage_tool = "specific_cov_tool",
                        patch_strip = 2,
                        patches = ["specific-patch.txt"],
                        platform = "aarch64-unknown-linux-gnu",
                        python_version = "3.13.0",
                        sha256 = "deadb00f",
                        strip_prefix = "python",
                        urls = ["something.org", "else.org"],
                    ),
                ],
                toolchain = [python_ext.toolchain(python_version = "3.13")],
            ),
        ),
        logger = repo_utils.logger(verbosity_level = 0, name = "python"),
    )

    env.expect.that_str(py.default_python_version).equals("3.13")
    env.expect.that_dict(py.config.default["tool_versions"]).contains_exactly({
        "3.13.0": {
            "coverage_tool": {"aarch64-unknown-linux-gnu": "specific_cov_tool"},
            "patch_strip": {"aarch64-apple-darwin": 1, "aarch64-unknown-linux-gnu": 2},
            "patches": {
                "aarch64-apple-darwin": ["common.txt"],
                "aarch64-unknown-linux-gnu": ["specific-patch.txt"],
            },
            "sha256": {"aarch64-apple-darwin": "deadbeef", "aarch64-unknown-linux-gnu": "deadb00f"},
            "strip_prefix": {"aarch64-apple-darwin": "prefix", "aarch64-unknown-linux-gnu": "python"},
            "url": {
                "aarch64-apple-darwin": ["example.org"],
                "aarch64-unknown-linux-gnu": ["something.org", "else.org"],
            },
        },
    })
    env.expect.that_dict(py.config.minor_mapping).contains_exactly({
        "3.13": "3.13.0",
    })
    env.expect.that_collection(py.toolchains).contains_exactly([
        struct(
            name = "python_3_13",
            python_version = "3.13",
            register_coverage_tool = False,
        ),
    ])

_tests.append(_test_add_patches)

def _test_fail_two_overrides(env):
    errors = []
    parse_modules(
        module_ctx = python_ext.mctx(
            python_ext.module(
                name = "my_module",
                is_root = True,
                override = [
                    python_ext.override(base_urls = ["foo"]),
                    python_ext.override(base_urls = ["bar"]),
                ],
                toolchain = [python_ext.toolchain(python_version = "3.13")],
            ),
        ),
        _fail = errors.append,
        logger = repo_utils.logger(verbosity_level = 0, name = "python"),
    )
    env.expect.that_collection(errors).contains_exactly([
        "Only a single 'python.override' can be present",
    ])

_tests.append(_test_fail_two_overrides)

def _test_single_version_override_errors(env):
    for test in [
        struct(
            overrides = [
                python_ext.single_version_override(
                    distutils_content = "foo",
                    python_version = "3.12.4",
                ),
                python_ext.single_version_override(
                    distutils_content = "foo",
                    python_version = "3.12.4",
                ),
            ],
            want_error = "Only a single 'python.single_version_override' can be present for '3.12.4'",
        ),
    ]:
        errors = []
        parse_modules(
            module_ctx = python_ext.mctx(
                python_ext.module(
                    name = "my_module",
                    is_root = True,
                    single_version_override = test.overrides,
                    toolchain = [python_ext.toolchain(python_version = "3.13")],
                ),
            ),
            _fail = errors.append,
            logger = repo_utils.logger(verbosity_level = 0, name = "python"),
        )
        env.expect.that_collection(errors).contains_exactly([test.want_error])

_tests.append(_test_single_version_override_errors)

def _test_single_version_platform_override_errors(env):
    for test in [
        struct(
            overrides = [
                python_ext.single_version_platform_override(
                    coverage_tool = "foo",
                    platform = "foo",
                    python_version = "3.12.4",
                ),
                python_ext.single_version_platform_override(
                    coverage_tool = "foo",
                    platform = "foo",
                    python_version = "3.12.4",
                ),
            ],
            want_error = "Only a single 'python.single_version_platform_override' can be present for '(\"3.12.4\", \"foo\")'",
        ),
        struct(
            overrides = [
                python_ext.single_version_platform_override(
                    platform = "foo",
                    python_version = "3.12",
                ),
            ],
            want_error = "The 'python_version' attribute needs to specify the full version in at least 'X.Y.Z' format, got: '3.12'",
        ),
        struct(
            overrides = [
                python_ext.single_version_platform_override(
                    platform = "foo",
                    python_version = "foo",
                ),
            ],
            want_error = "Failed to parse PEP 440 version identifier 'foo'. Parse error at 'foo'",
        ),
    ]:
        errors = []
        parse_modules(
            module_ctx = python_ext.mctx(
                python_ext.module(
                    name = "my_module",
                    is_root = True,
                    single_version_platform_override = test.overrides,
                    toolchain = [python_ext.toolchain(python_version = "3.13")],
                ),
            ),
            _fail = lambda *a: errors.append(" ".join(a)),
            logger = repo_utils.logger(verbosity_level = 0, name = "python"),
        )
        env.expect.that_collection(errors).contains_exactly([test.want_error])

_tests.append(_test_single_version_platform_override_errors)

# TODO @aignas 2024-09-03: add failure tests:
# * incorrect platform failure
# * missing python_version failure

def python_test_suite(name):
    """Create the test suite.

    Args:
        name: the name of the test suite
    """
    test_suite(name = name, basic_tests = _tests)

def register_python_tests(name):
    """Registers the python tests if Bzlmod is enabled, otherwise defines an empty test_suite.

    Args:
        name: The name of the test target.
    """
    if BZLMOD_ENABLED:
        python_test_suite(name = name)
    else:
        native.test_suite(
            name = name,
            tests = [],
        )
