"""Analysis tests for py_wheel_library."""

load("@bazel_skylib//rules:write_file.bzl", "write_file")
load("@rules_testing//lib:analysis_test.bzl", "analysis_test")
load("@rules_testing//lib:test_suite.bzl", "test_suite")
load("@rules_testing//lib:truth.bzl", "matching")
load("@rules_testing//lib:util.bzl", rt_util = "util")
load("//python:py_info.bzl", "PyInfo")
load("//python/private:common_labels.bzl", "labels")  # buildifier: disable=bzl-visibility
load("//python/private/pypi:py_wheel_library.bzl", "py_wheel_library")  # buildifier: disable=bzl-visibility
load("//tests/support:py_info_subject.bzl", "py_info_subject")
load(
    "//tests/support:support.bzl",
    "CC_TOOLCHAIN",
    "PY_TOOLCHAINS",
)

_COMMON_CONFIG_SETTINGS = {
    "//command_line_option:allow_unresolved_symlinks": True,
    "//command_line_option:extra_toolchains": [PY_TOOLCHAINS, CC_TOOLCHAIN],
    labels.EXEC_TOOLS_TOOLCHAIN: "enabled",
    labels.PRECOMPILE: "auto",
    labels.PRECOMPILE_SOURCE_RETENTION: "keep_source",
}

_tests = []

def _test_pyi_files_exposed_when_stubs_present(name):
    rt_util.helper_target(
        write_file,
        name = name + "_whl",
        out = name + ".whl",
    )
    rt_util.helper_target(
        py_wheel_library,
        name = name + "_with_pyi",
        wheel = name + "_whl",
        extracted_files = [
            "site-packages/foo/__init__.py",
            "site-packages/foo/__init__.pyi",
        ],
    )
    rt_util.helper_target(
        py_wheel_library,
        name = name + "_with_py_typed",
        wheel = name + "_whl",
        extracted_files = [
            "site-packages/foo/__init__.py",
            "site-packages/foo/py.typed",
        ],
    )
    rt_util.helper_target(
        py_wheel_library,
        name = name + "_with_py_typed_omit",
        wheel = name + "_whl",
        extracted_files = [
            "site-packages/foo/__init__.py",
            "site-packages/foo/py.typed",
        ],
        precompile = "enabled",
        precompile_source_retention = "omit_source",
    )
    rt_util.helper_target(
        py_wheel_library,
        name = name + "_no_stubs",
        wheel = name + "_whl",
        extracted_files = [
            "site-packages/foo/__init__.py",
        ],
    )
    rt_util.helper_target(
        py_wheel_library,
        name = name + "_sdist_site_paths",
        wheel = name + "_whl",
        distribution = "foo",
        version = "1.0",
        site_paths = ["foo"],
    )
    rt_util.helper_target(
        py_wheel_library,
        name = name + "_sdist_site_paths_with_pyi",
        wheel = name + "_whl",
        distribution = "foo",
        version = "1.0",
        site_paths = ["foo", "foo/__init__.pyi"],
    )
    analysis_test(
        name = name,
        impl = _test_pyi_files_exposed_when_stubs_present_impl,
        targets = {
            "no_stubs": name + "_no_stubs",
            "sdist_site_paths": name + "_sdist_site_paths",
            "sdist_site_paths_with_pyi": name + "_sdist_site_paths_with_pyi",
            "with_py_typed": name + "_with_py_typed",
            "with_py_typed_omit": name + "_with_py_typed_omit",
            "with_pyi": name + "_with_pyi",
        },
        config_settings = _COMMON_CONFIG_SETTINGS,
    )

def _test_pyi_files_exposed_when_stubs_present_impl(env, targets):
    with_pyi_info = env.expect.that_target(targets.with_pyi).provider(
        PyInfo,
        factory = py_info_subject,
    )
    with_pyi_info.direct_pyi_files().contains_exactly([
        "{package}/" + targets.with_pyi.label.name,
    ])
    with_py_typed_info = env.expect.that_target(targets.with_py_typed).provider(
        PyInfo,
        factory = py_info_subject,
    )
    with_py_typed_info.direct_pyi_files().contains_exactly([
        "{package}/" + targets.with_py_typed.label.name,
    ])
    with_py_typed_omit_info = env.expect.that_target(targets.with_py_typed_omit).provider(
        PyInfo,
        factory = py_info_subject,
    )
    with_py_typed_omit_info.direct_pyi_files().contains_exactly([])
    no_stubs_info = env.expect.that_target(targets.no_stubs).provider(
        PyInfo,
        factory = py_info_subject,
    )
    no_stubs_info.direct_pyi_files().contains_exactly([])
    sdist_site_paths_info = env.expect.that_target(targets.sdist_site_paths).provider(
        PyInfo,
        factory = py_info_subject,
    )
    sdist_site_paths_info.direct_pyi_files().contains_exactly([])
    sdist_site_paths_with_pyi_info = env.expect.that_target(targets.sdist_site_paths_with_pyi).provider(
        PyInfo,
        factory = py_info_subject,
    )
    sdist_site_paths_with_pyi_info.direct_pyi_files().contains_exactly([
        "{package}/" + targets.sdist_site_paths_with_pyi.label.name,
    ])

_tests.append(_test_pyi_files_exposed_when_stubs_present)

def _test_precompile_flags_and_providers(name):
    rt_util.helper_target(
        write_file,
        name = name + "_whl",
        out = name + ".whl",
    )
    rt_util.helper_target(
        py_wheel_library,
        name = name + "_default",
        wheel = name + "_whl",
        extracted_files = ["site-packages/foo/__init__.py"],
    )
    rt_util.helper_target(
        py_wheel_library,
        name = name + "_enabled",
        wheel = name + "_whl",
        extracted_files = ["site-packages/foo/__init__.py"],
        precompile = "enabled",
    )
    rt_util.helper_target(
        py_wheel_library,
        name = name + "_omit_source",
        wheel = name + "_whl",
        extracted_files = ["site-packages/foo/__init__.py"],
        precompile = "enabled",
        precompile_source_retention = "omit_source",
    )
    analysis_test(
        name = name,
        impl = _test_precompile_flags_and_providers_impl,
        targets = {
            "default": name + "_default",
            "enabled": name + "_enabled",
            "omit_source": name + "_omit_source",
        },
        config_settings = _COMMON_CONFIG_SETTINGS,
    )

def _test_precompile_flags_and_providers_impl(env, targets):
    default_t = env.expect.that_target(targets.default)
    default_info = default_t.provider(PyInfo, factory = py_info_subject)
    default_info.direct_pyc_files().contains_exactly([])
    default_info.transitive_sources().contains_exactly([
        "{package}/" + targets.default.label.name,
    ])
    default_t.output_group("dist_info").contains_exactly([
        "{package}/" + targets.default.label.name + ".dist_info/entry_points.txt",
    ])
    default_t.action_generating("{package}/" + targets.default.label.name).argv().contains_at_least([
        "--entry-points-output",
    ])

    enabled_t = env.expect.that_target(targets.enabled)
    enabled_info = enabled_t.provider(PyInfo, factory = py_info_subject)
    enabled_info.direct_pyc_files().contains_exactly([
        "{package}/" + targets.enabled.label.name,
    ])
    enabled_info.transitive_sources().contains_exactly([
        "{package}/" + targets.enabled.label.name,
    ])
    enabled_t.action_generating("{package}/" + targets.enabled.label.name).argv().contains_at_least([
        "--precompile",
        "--pyc-tag",
        "fakepy-45",
        "--precompile-invalidation-mode",
        "checked_hash",
        "--precompile-source-retention",
        "keep_source",
    ])

    omit_t = env.expect.that_target(targets.omit_source)
    omit_info = omit_t.provider(PyInfo, factory = py_info_subject)
    omit_info.direct_pyc_files().contains_exactly([
        "{package}/" + targets.omit_source.label.name,
    ])
    omit_info.transitive_sources().contains_exactly([])
    omit_t.action_generating("{package}/" + targets.omit_source.label.name).argv().contains_at_least([
        "--precompile",
        "--precompile-source-retention",
        "omit_source",
    ])

_tests.append(_test_precompile_flags_and_providers)

def _test_package_and_version_from_dist_info(name):
    rt_util.helper_target(
        write_file,
        name = name + "_whl",
        out = name + ".whl",
    )
    rt_util.helper_target(
        py_wheel_library,
        name = name + "_from_metadata",
        wheel = name + "_whl",
        extracted_files = [
            "site-packages/My_Pkg-1.2.0.dist-info/METADATA",
            "site-packages/my_pkg/__init__.py",
            "site-packages/my_pkg/_vendor/vendored-9.9.0.dist-info/METADATA",
        ],
        experimental_venvs_site_packages = labels.VENVS_SITE_PACKAGES,
    )
    rt_util.helper_target(
        py_wheel_library,
        name = name + "_from_tags",
        wheel = name + "_whl",
        extracted_files = [
            "site-packages/tag_pkg/__init__.py",
        ],
        tags = [
            "pypi_name=Tag_Pkg",
            "pypi_version=2.3.0",
        ],
        experimental_venvs_site_packages = labels.VENVS_SITE_PACKAGES,
    )
    analysis_test(
        name = name,
        impl = _test_package_and_version_from_dist_info_impl,
        targets = {
            "from_metadata": name + "_from_metadata",
            "from_tags": name + "_from_tags",
        },
        config_settings = _COMMON_CONFIG_SETTINGS | {
            labels.VENVS_SITE_PACKAGES: "yes",
        },
    )

def _test_package_and_version_from_dist_info_impl(env, targets):
    meta_entries = targets.from_metadata[PyInfo].venv_symlinks.to_list()
    env.expect.that_collection([
        (e.venv_path, e.package, e.version)
        for e in meta_entries
    ]).contains_exactly([
        ("My_Pkg-1.2.0.dist-info", "my_pkg", "1.2.0"),
        ("my_pkg", "my_pkg", "1.2.0"),
    ])

    tag_entries = targets.from_tags[PyInfo].venv_symlinks.to_list()
    env.expect.that_collection([
        (e.venv_path, e.package, e.version)
        for e in tag_entries
    ]).contains_exactly([
        ("tag_pkg", "tag_pkg", "2.3.0"),
    ])

_tests.append(_test_package_and_version_from_dist_info)

def _test_missing_exec_tools_toolchain_fails(name):
    rt_util.helper_target(
        write_file,
        name = name + "_whl",
        out = name + ".whl",
    )
    rt_util.helper_target(
        py_wheel_library,
        name = name + "_subject",
        wheel = name + "_whl",
        extracted_files = ["site-packages/foo/__init__.py"],
    )
    analysis_test(
        name = name,
        impl = _test_missing_exec_tools_toolchain_fails_impl,
        target = name + "_subject",
        expect_failure = True,
        config_settings = _COMMON_CONFIG_SETTINGS | {
            "//command_line_option:extra_toolchains": [
                str(Label("//tests/support/py_toolchains:platform_toolchain")),
                CC_TOOLCHAIN,
            ],
            labels.EXEC_TOOLS_TOOLCHAIN: "disabled",
        },
    )

def _test_missing_exec_tools_toolchain_fails_impl(env, target):
    env.expect.that_target(target).failures().contains_predicate(
        matching.contains("experimental_action_install requires the exec_tools toolchain"),
    )

_tests.append(_test_missing_exec_tools_toolchain_fails)

def py_wheel_library_bzl_test_suite(name):
    test_suite(
        name = name,
        tests = _tests,
    )
