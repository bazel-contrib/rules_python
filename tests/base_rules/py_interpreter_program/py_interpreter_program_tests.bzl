"""Tests for py_interpreter_program."""

load("@rules_testing//lib:analysis_test.bzl", "analysis_test")
load("@rules_testing//lib:test_suite.bzl", "test_suite")
load("@rules_testing//lib:truth.bzl", "matching")
load("@rules_testing//lib:util.bzl", rt_util = "util")
load("//python/private:common.bzl", "actions_run")  # buildifier: disable=bzl-visibility
load("//python/private:py_interpreter_program.bzl", "PyInterpreterProgramInfo", "py_interpreter_program")  # buildifier: disable=bzl-visibility
load("//python/private:toolchain_types.bzl", "EXEC_TOOLS_TOOLCHAIN_TYPE")  # buildifier: disable=bzl-visibility

_tests = []

def _run_interpreter_program_impl(ctx):
    out = ctx.actions.declare_file(ctx.label.name + ".txt")
    args = ctx.actions.args()
    args.add(out)
    actions_run(
        ctx,
        executable = ctx.attr._program,
        arguments = [args],
        outputs = [out],
        mnemonic = "TestPyInterpreterProgram",
        progress_message = "Testing py_interpreter_program with srcs: %{label}",
    )
    return [DefaultInfo(files = depset([out]))]

_run_interpreter_program_rule = rule(
    implementation = _run_interpreter_program_impl,
    attrs = {
        "_program": attr.label(
            default = ":sample_program_with_srcs",
            cfg = "exec",
        ),
    },
    toolchains = [EXEC_TOOLS_TOOLCHAIN_TYPE],
)

def run_interpreter_program(name, **kwargs):
    py_interpreter_program(
        name = "sample_program_with_srcs",
        main = "main_prog.py",
        srcs = ["helper_mod.py"],
        tags = ["manual"],
    )
    _run_interpreter_program_rule(
        name = name,
        **kwargs
    )

def _test_empty_srcs_unchanged(name):
    rt_util.helper_target(
        py_interpreter_program,
        name = name + "_prog",
        main = "main_prog.py",
    )
    analysis_test(
        name = name,
        impl = _test_empty_srcs_unchanged_impl,
        target = name + "_prog",
    )

_tests.append(_test_empty_srcs_unchanged)

def _test_empty_srcs_unchanged_impl(env, target):
    files = [f.short_path for f in target[DefaultInfo].files.to_list()]
    env.expect.that_collection(files).contains_exactly([
        "{}/{}_prog_.py".format(env.ctx.label.package, env.ctx.label.name),
    ])
    info = target[PyInterpreterProgramInfo]
    env.expect.that_dict(info.env).contains_exactly({})
    env.expect.that_collection(info.interpreter_args).contains_exactly([])

def _test_srcs_staged_as_siblings(name):
    rt_util.helper_target(
        py_interpreter_program,
        name = name + "_prog",
        main = "main_prog.py",
        srcs = ["helper_mod.py"],
    )
    analysis_test(
        name = name,
        impl = _test_srcs_staged_as_siblings_impl,
        target = name + "_prog",
    )

_tests.append(_test_srcs_staged_as_siblings)

def _test_srcs_staged_as_siblings_impl(env, target):
    pkg = env.ctx.label.package
    prefix = "{}/{}_prog_".format(pkg, env.ctx.label.name)
    files = [f.short_path for f in target[DefaultInfo].files.to_list()]
    env.expect.that_collection(files).contains_exactly([
        prefix + "/helper_mod.py",
        prefix + "/main_prog.py",
    ])
    env.expect.that_str(target[DefaultInfo].files_to_run.executable.short_path).equals(
        prefix + "/main_prog.py",
    )
    info = target[PyInterpreterProgramInfo]
    env.expect.that_dict(info.env).contains_exactly({
        "PYTHONDONTWRITEBYTECODE": "1",
    })
    env.expect.that_collection(info.interpreter_args).contains_exactly(["-B"])

def _test_duplicate_basename_fails(name):
    rt_util.helper_target(
        py_interpreter_program,
        name = name + "_prog",
        main = "main_prog.py",
        srcs = ["sub/main_prog.py"],
    )
    analysis_test(
        name = name,
        impl = _test_duplicate_basename_fails_impl,
        target = name + "_prog",
        expect_failure = True,
    )

_tests.append(_test_duplicate_basename_fails)

def _test_duplicate_basename_fails_impl(env, target):
    env.expect.that_target(target).failures().contains_predicate(
        matching.contains("duplicate basename 'main_prog.py'"),
    )

def py_interpreter_program_test_suite(name):
    test_suite(
        name = name,
        tests = _tests,
    )
