"""Test for py_library."""

load("@rules_testing//lib:analysis_test.bzl", "analysis_test")
load("@rules_testing//lib:truth.bzl", "matching")
load("@rules_testing//lib:util.bzl", rt_util = "util")
load("//python:py_info.bzl", "PyInfo")
load("//python:py_library.bzl", "py_library")
load("//python:py_runtime_info.bzl", "PyRuntimeInfo")
load("//tests/base_rules:base_tests.bzl", "create_base_tests")
load("//tests/base_rules:util.bzl", pt_util = "util")
load("//tests/support:py_info_subject.bzl", "py_info_subject")

_tests = []

def _tree_artifact_impl(ctx):
    out = ctx.actions.declare_directory(ctx.label.name + ".dir")
    ctx.actions.run_shell(
        outputs = [out],
        command = "mkdir -p \"$1\"",
        arguments = [out.path],
    )
    return [DefaultInfo(files = depset([out]))]

_tree_artifact = rule(implementation = _tree_artifact_impl)

def _non_py_py_info_impl(ctx):
    return [
        DefaultInfo(files = depset(ctx.files.srcs)),
        PyInfo(transitive_sources = depset()),
    ]

_non_py_py_info = rule(
    implementation = _non_py_py_info_impl,
    attrs = {"srcs": attr.label_list(allow_files = True)},
)

def _test_py_runtime_info_not_present(name, config):
    rt_util.helper_target(
        config.rule,
        name = name + "_subject",
        srcs = ["lib.py"],
    )
    analysis_test(
        name = name,
        target = name + "_subject",
        impl = _test_py_runtime_info_not_present_impl,
    )

def _test_py_runtime_info_not_present_impl(env, target):
    env.expect.that_bool(PyRuntimeInfo in target).equals(False)

_tests.append(_test_py_runtime_info_not_present)

def _test_default_outputs(name, config):
    rt_util.helper_target(
        config.rule,
        name = name + "_subject",
        srcs = ["lib.py"],
    )
    analysis_test(
        name = name,
        target = name + "_subject",
        impl = _test_default_outputs_impl,
    )

def _test_default_outputs_impl(env, target):
    env.expect.that_target(target).default_outputs().contains_exactly([
        "{package}/lib.py",
    ])

_tests.append(_test_default_outputs)

def _test_srcs_can_contain_rule_generating_py_and_nonpy_files(name, config):
    rt_util.helper_target(
        config.rule,
        name = name + "_subject",
        srcs = ["lib.py", name + "_gensrcs"],
    )
    rt_util.helper_target(
        native.genrule,
        name = name + "_gensrcs",
        cmd = "touch $(OUTS)",
        outs = [name + "_gen.py", name + "_gen.cc"],
    )
    analysis_test(
        name = name,
        target = name + "_subject",
        impl = _test_srcs_can_contain_rule_generating_py_and_nonpy_files_impl,
    )

def _test_srcs_can_contain_rule_generating_py_and_nonpy_files_impl(env, target):
    env.expect.that_target(target).default_outputs().contains_exactly([
        "{package}/{test_name}_gen.py",
        "{package}/lib.py",
    ])

_tests.append(_test_srcs_can_contain_rule_generating_py_and_nonpy_files)

def _test_srcs_can_contain_empty_py_library(name, config):
    rt_util.helper_target(
        config.rule,
        name = name + "_empty",
    )
    rt_util.helper_target(
        config.rule,
        name = name + "_subject",
        srcs = [name + "_empty"],
    )
    analysis_test(
        name = name,
        target = name + "_subject",
        impl = _test_srcs_can_contain_empty_py_library_impl,
    )

def _test_srcs_can_contain_empty_py_library_impl(env, target):
    env.expect.that_target(target).default_outputs().contains_exactly([])

_tests.append(_test_srcs_can_contain_empty_py_library)

def _test_srcs_can_contain_tree_artifact(name, config):
    rt_util.helper_target(
        _tree_artifact,
        name = name + "_tree",
    )
    rt_util.helper_target(
        config.rule,
        name = name + "_subject",
        srcs = [name + "_tree"],
    )
    analysis_test(
        name = name,
        target = name + "_subject",
        impl = _test_srcs_can_contain_tree_artifact_impl,
    )

def _test_srcs_can_contain_tree_artifact_impl(env, target):
    env.expect.that_target(target).default_outputs().contains_exactly([])

_tests.append(_test_srcs_can_contain_tree_artifact)

def _test_srcs_direct_non_py_file_is_error(name, config):
    rt_util.helper_target(
        config.rule,
        name = name + "_subject",
        srcs = [rt_util.empty_file(name + ".txt")],
    )
    analysis_test(
        name = name,
        target = name + "_subject",
        impl = _test_srcs_direct_non_py_file_is_error_impl,
        expect_failure = True,
    )

def _test_srcs_direct_non_py_file_is_error_impl(env, target):
    env.expect.that_target(target).failures().contains_predicate(
        matching.str_matches("does not produce*srcs files"),
    )

_tests.append(_test_srcs_direct_non_py_file_is_error)

def _test_srcs_empty_filegroup_is_error(name, config):
    rt_util.helper_target(
        native.filegroup,
        name = name + "_empty",
    )
    rt_util.helper_target(
        config.rule,
        name = name + "_subject",
        srcs = [name + "_empty"],
    )
    analysis_test(
        name = name,
        target = name + "_subject",
        impl = _test_srcs_empty_filegroup_is_error_impl,
        expect_failure = True,
    )

def _test_srcs_empty_filegroup_is_error_impl(env, target):
    env.expect.that_target(target).failures().contains_predicate(
        matching.str_matches("does not produce*srcs files"),
    )

_tests.append(_test_srcs_empty_filegroup_is_error)

def _test_srcs_py_info_with_only_non_py_files_is_error(name, config):
    rt_util.helper_target(
        _non_py_py_info,
        name = name + "_non_py",
        srcs = [rt_util.empty_file(name + ".txt")],
    )
    rt_util.helper_target(
        config.rule,
        name = name + "_subject",
        srcs = [name + "_non_py"],
    )
    analysis_test(
        name = name,
        target = name + "_subject",
        impl = _test_srcs_py_info_with_only_non_py_files_is_error_impl,
        expect_failure = True,
    )

def _test_srcs_py_info_with_only_non_py_files_is_error_impl(env, target):
    env.expect.that_target(target).failures().contains_predicate(
        matching.str_matches("does not produce*srcs files"),
    )

_tests.append(_test_srcs_py_info_with_only_non_py_files_is_error)

def _test_srcs_generating_no_py_files_is_error(name, config):
    rt_util.helper_target(
        config.rule,
        name = name + "_subject",
        srcs = [name + "_gen"],
    )
    rt_util.helper_target(
        native.genrule,
        name = name + "_gen",
        cmd = "touch $(OUTS)",
        outs = [name + "_gen.cc"],
    )
    analysis_test(
        name = name,
        target = name + "_subject",
        impl = _test_srcs_generating_no_py_files_is_error_impl,
        expect_failure = True,
    )

def _test_srcs_generating_no_py_files_is_error_impl(env, target):
    env.expect.that_target(target).failures().contains_predicate(
        matching.str_matches("does not produce*srcs files"),
    )

_tests.append(_test_srcs_generating_no_py_files_is_error)

def _test_files_to_compile(name, config):
    rt_util.helper_target(
        config.rule,
        name = name + "_subject",
        srcs = ["lib1.py"],
        deps = [name + "_lib2"],
    )
    rt_util.helper_target(
        config.rule,
        name = name + "_lib2",
        srcs = ["lib2.py"],
        deps = [name + "_lib3"],
    )
    rt_util.helper_target(
        config.rule,
        name = name + "_lib3",
        srcs = ["lib3.py"],
    )
    analysis_test(
        name = name,
        target = name + "_subject",
        impl = _test_files_to_compile_impl,
    )

def _test_files_to_compile_impl(env, target):
    target = env.expect.that_target(target)
    target.output_group(
        "compilation_prerequisites_INTERNAL_",
    ).contains_exactly([
        "{package}/lib1.py",
        "{package}/lib2.py",
        "{package}/lib3.py",
    ])
    target.output_group(
        "compilation_outputs",
    ).contains_exactly([
        "{package}/lib1.py",
        "{package}/lib2.py",
        "{package}/lib3.py",
    ])

_tests.append(_test_files_to_compile)

def _test_pyi_srcs_not_propagated_via_srcs(name, config):
    rt_util.helper_target(
        config.rule,
        name = name + "_lib",
        srcs = ["lib.py"],
        pyi_srcs = ["lib.pyi"],
    )
    rt_util.helper_target(
        config.rule,
        name = name + "_subject",
        srcs = [name + "_lib"],
    )
    analysis_test(
        name = name,
        target = name + "_subject",
        impl = _test_pyi_srcs_not_propagated_via_srcs_impl,
    )

def _test_pyi_srcs_not_propagated_via_srcs_impl(env, target):
    info = env.expect.that_target(target).provider(
        PyInfo,
        factory = py_info_subject,
    )
    info.transitive_pyi_files().contains_exactly([])

_tests.append(_test_pyi_srcs_not_propagated_via_srcs)

def _test_pyi_srcs_propagated_via_deps(name, config):
    rt_util.helper_target(
        config.rule,
        name = name + "_lib",
        srcs = ["lib.py"],
        pyi_srcs = ["lib.pyi"],
    )
    rt_util.helper_target(
        config.rule,
        name = name + "_subject",
        srcs = [name + "_lib"],
        deps = [name + "_lib"],
    )
    analysis_test(
        name = name,
        target = name + "_subject",
        impl = _test_pyi_srcs_propagated_via_deps_impl,
    )

def _test_pyi_srcs_propagated_via_deps_impl(env, target):
    info = env.expect.that_target(target).provider(
        PyInfo,
        factory = py_info_subject,
    )
    info.transitive_pyi_files().contains_exactly([
        "{package}/lib.pyi",
    ])

_tests.append(_test_pyi_srcs_propagated_via_deps)

def py_library_test_suite(name):
    config = struct(rule = py_library, base_test_rule = py_library)
    native.test_suite(
        name = name,
        tests = pt_util.create_tests(_tests, config = config) + create_base_tests(config),
    )
