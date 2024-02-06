# Copyright 2022 The Bazel Authors. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

"""Create a repository to hold the toolchains.

This follows guidance here:
https://docs.bazel.build/versions/main/skylark/deploying.html#registering-toolchains

The "complex computation" in our case is simply downloading large artifacts.
This guidance tells us how to avoid that: we put the toolchain targets in the
alias repository with only the toolchain attribute pointing into the
platform-specific repositories.
"""

load(
    "//python:versions.bzl",
    "LINUX_NAME",
    "MACOS_NAME",
    "PLATFORMS",
    "WINDOWS_NAME",
)
load("//python/private:repo_utils.bzl", "REPO_DEBUG_ENV_VAR", "repo_utils")

def get_repository_name(repository_workspace):
    dummy_label = "//:_"
    return str(repository_workspace.relative(dummy_label))[:-len(dummy_label)] or "@"

def python_toolchain_build_file_content(
        prefix,
        python_version,
        set_python_version_constraint,
        user_repository_name):
    """Creates the content for toolchain definitions for a build file.

    Args:
        prefix: Python toolchain name prefixes
        python_version: Python versions for the toolchains
        set_python_version_constraint: string, "True" if the toolchain should
            have the Python version constraint added as a requirement for
            matching the toolchain, "False" if not.
        user_repository_name: names for the user repos

    Returns:
        build_content: Text containing toolchain definitions
    """

    # We create a list of toolchain content from iterating over
    # the enumeration of PLATFORMS.  We enumerate PLATFORMS in
    # order to get us an index to increment the increment.
    return "\n\n".join([
        """\
py_toolchain_suite(
    user_repository_name = "{user_repository_name}_{platform}",
    prefix = "{prefix}{platform}",
    target_compatible_with = {compatible_with},
    python_version = "{python_version}",
    set_python_version_constraint = "{set_python_version_constraint}",
)""".format(
            compatible_with = meta.compatible_with,
            platform = platform,
            set_python_version_constraint = set_python_version_constraint,
            user_repository_name = user_repository_name,
            prefix = prefix,
            python_version = python_version,
        )
        for platform, meta in PLATFORMS.items()
    ])

def _toolchains_repo_impl(rctx):
    build_content = """\
# Generated by python/private/toolchains_repo.bzl
#
# These can be registered in the workspace file or passed to --extra_toolchains
# flag. By default all these toolchains are registered by the
# python_register_toolchains macro so you don't normally need to interact with
# these targets.

load("@{rules_python}//python/private:py_toolchain_suite.bzl", "py_toolchain_suite")

""".format(
        rules_python = rctx.attr._rules_python_workspace.workspace_name,
    )

    toolchains = python_toolchain_build_file_content(
        prefix = "",
        python_version = rctx.attr.python_version,
        set_python_version_constraint = str(rctx.attr.set_python_version_constraint),
        user_repository_name = rctx.attr.user_repository_name,
    )

    rctx.file("BUILD.bazel", build_content + toolchains)

toolchains_repo = repository_rule(
    _toolchains_repo_impl,
    doc = "Creates a repository with toolchain definitions for all known platforms " +
          "which can be registered or selected.",
    attrs = {
        "python_version": attr.string(doc = "The Python version."),
        "set_python_version_constraint": attr.bool(doc = "if target_compatible_with for the toolchain should set the version constraint"),
        "user_repository_name": attr.string(doc = "what the user chose for the base name"),
        "_rules_python_workspace": attr.label(default = Label("//:WORKSPACE")),
    },
)

def _toolchain_aliases_impl(rctx):
    (os_name, arch) = get_host_os_arch(rctx)

    host_platform = get_host_platform(os_name, arch)

    is_windows = (os_name == WINDOWS_NAME)
    python3_binary_path = "python.exe" if is_windows else "bin/python3"

    # Base BUILD file for this repository.
    build_contents = """\
# Generated by python/private/toolchains_repo.bzl
package(default_visibility = ["//visibility:public"])
load("@rules_python//python:versions.bzl", "gen_python_config_settings")
gen_python_config_settings()
exports_files(["defs.bzl"])

PLATFORMS = [
{loaded_platforms}
]
alias(name = "files",           actual = select({{":" + item: "@{py_repository}_" + item + "//:files" for item in PLATFORMS}}))
alias(name = "includes",        actual = select({{":" + item: "@{py_repository}_" + item + "//:includes" for item in PLATFORMS}}))
alias(name = "libpython",       actual = select({{":" + item: "@{py_repository}_" + item + "//:libpython" for item in PLATFORMS}}))
alias(name = "py3_runtime",     actual = select({{":" + item: "@{py_repository}_" + item + "//:py3_runtime" for item in PLATFORMS}}))
alias(name = "python_headers",  actual = select({{":" + item: "@{py_repository}_" + item + "//:python_headers" for item in PLATFORMS}}))
alias(name = "python_runtimes", actual = select({{":" + item: "@{py_repository}_" + item + "//:python_runtimes" for item in PLATFORMS}}))
alias(name = "python3",         actual = select({{":" + item: "@{py_repository}_" + item + "//:" + ("python.exe" if "windows" in item else "bin/python3") for item in PLATFORMS}}))
""".format(
        py_repository = rctx.attr.user_repository_name,
        loaded_platforms = "\n".join(["    \"{}\",".format(p) for p in rctx.attr.platforms]),
    )
    if not is_windows:
        build_contents += """\
alias(name = "pip",             actual = select({{":" + item: "@{py_repository}_" + item + "//:python_runtimes" for item in PLATFORMS if "windows" not in item}}))
""".format(
            py_repository = rctx.attr.user_repository_name,
            host_platform = host_platform,
        )
    rctx.file("BUILD.bazel", build_contents)

    # Expose a Starlark file so rules can know what host platform we used and where to find an interpreter
    # when using repository_ctx.path, which doesn't understand aliases.
    rctx.file("defs.bzl", content = """\
# Generated by python/private/toolchains_repo.bzl

load(
    "{rules_python}//python/config_settings:transition.bzl",
    _py_binary = "py_binary",
    _py_test = "py_test",
)
load(
    "{rules_python}//python/entry_points:py_console_script_binary.bzl",
    _py_console_script_binary = "py_console_script_binary",
)
load("{rules_python}//python:pip.bzl", _compile_pip_requirements = "compile_pip_requirements")

host_platform = "{host_platform}"
interpreter = "@{py_repository}_{host_platform}//:{python3_binary_path}"

def py_binary(name, **kwargs):
    return _py_binary(
        name = name,
        python_version = "{python_version}",
        **kwargs
    )

def py_console_script_binary(name, **kwargs):
    return _py_console_script_binary(
        name = name,
        binary_rule = py_binary,
        **kwargs
    )

def py_test(name, **kwargs):
    return _py_test(
        name = name,
        python_version = "{python_version}",
        **kwargs
    )

def compile_pip_requirements(name, **kwargs):
    return _compile_pip_requirements(
        name = name,
        py_binary = py_binary,
        py_test = py_test,
        **kwargs
    )

""".format(
        host_platform = host_platform,
        py_repository = rctx.attr.user_repository_name,
        python_version = rctx.attr.python_version,
        python3_binary_path = python3_binary_path,
        rules_python = get_repository_name(rctx.attr._rules_python_workspace),
    ))

toolchain_aliases = repository_rule(
    _toolchain_aliases_impl,
    doc = """\
Creates a repository with a shorter name only referencing the python version,
it contains a BUILD.bazel file declaring aliases to the host platform's targets
and is a great fit for any usage related to setting up toolchains for build
actions.""",
    attrs = {
        "platforms": attr.string_list(
            doc = "List of platforms for which aliases shall be created",
        ),
        "python_version": attr.string(doc = "The Python version."),
        "user_repository_name": attr.string(
            mandatory = True,
            doc = "The base name for all created repositories, like 'python38'.",
        ),
        "_rules_python_workspace": attr.label(default = Label("//:WORKSPACE")),
    },
    environ = [REPO_DEBUG_ENV_VAR],
)

def _host_toolchain_impl(rctx):
    rctx.file("BUILD.bazel", """\
# Generated by python/private/toolchains_repo.bzl

exports_files(["python"], visibility = ["//visibility:public"])
""")

    (os_name, arch) = get_host_os_arch(rctx)
    host_platform = get_host_platform(os_name, arch)
    repo = "@@{py_repository}_{host_platform}".format(
        py_repository = rctx.attr.name[:-len("_host")],
        host_platform = host_platform,
    )

    rctx.report_progress("Symlinking interpreter files to the target platform")
    host_python_repo = rctx.path(Label("{repo}//:BUILD.bazel".format(repo = repo)))

    # The interpreter might not work on platfroms that don't have symlink support if
    # we just symlink the interpreter itself. rctx.symlink does a copy in such cases
    # so we can just attempt to symlink all of the directories in the host interpreter
    # repo, which should be faster than re-downloading it.
    for p in host_python_repo.dirname.readdir():
        if p.basename in [
            # ignore special files created by the repo rule automatically
            "BUILD.bazel",
            "MODULE.bazel",
            "REPO.bazel",
            "WORKSPACE",
            "WORKSPACE.bazel",
            "WORKSPACE.bzlmod",
        ]:
            continue

        # Use the symlink command as it will create copies if the symlinks are not
        # supported, let's hope it handles directories, otherwise we'll have to do this in a very inefficient way.
        rctx.symlink(p, p.basename)

    is_windows = (os_name == WINDOWS_NAME)
    python_binary = "python.exe" if is_windows else "python"

    # Ensure that we can run the interpreter and check that we are not
    # using the host interpreter.
    python_tester_contents = """\
from pathlib import Path
import sys

python = Path(sys.executable)
want_python = str(Path("{python}").resolve())
got_python = str(Path(sys.executable).resolve())

assert want_python == got_python, \
    "Expected to use a different interpreter:\\nwant: '{{}}'\\n got: '{{}}'".format(
        want_python,
        got_python,
    )
""".format(repo = repo.strip("@"), python = python_binary)
    python_tester = rctx.path("python_tester.py")
    rctx.file(python_tester, python_tester_contents)
    repo_utils.execute_checked(
        rctx,
        op = "CheckHostInterpreter",
        arguments = [rctx.path(python_binary), python_tester],
    )
    if not rctx.delete(python_tester):
        fail("Failed to delete the python tester")

host_toolchain = repository_rule(
    _host_toolchain_impl,
    doc = """\
Creates a repository with a shorter name meant to be used in the repository_ctx,
which needs to have `symlinks` for the interpreter. This is separate from the
toolchain_aliases repo because referencing the `python` interpreter target from
this repo causes an eager fetch of the toolchain for the host platform.
    """,
    attrs = {
        "platforms": attr.string_list(
            doc = "List of platforms for which aliases shall be created",
        ),
        "python_version": attr.string(doc = "The Python version."),
        "user_repository_name": attr.string(
            mandatory = True,
            doc = "The base name for all created repositories, like 'python38'.",
        ),
        "_rules_python_workspace": attr.label(default = Label("//:WORKSPACE")),
    },
)

def _multi_toolchain_aliases_impl(rctx):
    rules_python = rctx.attr._rules_python_workspace.workspace_name

    for python_version, repository_name in rctx.attr.python_versions.items():
        file = "{}/defs.bzl".format(python_version)
        rctx.file(file, content = """\
# Generated by python/private/toolchains_repo.bzl

load(
    "@{repository_name}//:defs.bzl",
    _compile_pip_requirements = "compile_pip_requirements",
    _host_platform = "host_platform",
    _interpreter = "interpreter",
    _py_binary = "py_binary",
    _py_console_script_binary = "py_console_script_binary",
    _py_test = "py_test",
)

compile_pip_requirements = _compile_pip_requirements
host_platform = _host_platform
interpreter = _interpreter
py_binary = _py_binary
py_console_script_binary = _py_console_script_binary
py_test = _py_test
""".format(
            repository_name = repository_name,
        ))
        rctx.file("{}/BUILD.bazel".format(python_version), "")

    pip_bzl = """\
# Generated by python/private/toolchains_repo.bzl

load("@{rules_python}//python:pip.bzl", "pip_parse", _multi_pip_parse = "multi_pip_parse")

def multi_pip_parse(name, requirements_lock, **kwargs):
    return _multi_pip_parse(
        name = name,
        python_versions = {python_versions},
        requirements_lock = requirements_lock,
        **kwargs
    )

""".format(
        python_versions = rctx.attr.python_versions.keys(),
        rules_python = rules_python,
    )
    rctx.file("pip.bzl", content = pip_bzl)
    rctx.file("BUILD.bazel", "")

multi_toolchain_aliases = repository_rule(
    _multi_toolchain_aliases_impl,
    attrs = {
        "python_versions": attr.string_dict(doc = "The Python versions."),
        "_rules_python_workspace": attr.label(default = Label("//:WORKSPACE")),
    },
)

def sanitize_platform_name(platform):
    return platform.replace("-", "_")

def get_host_platform(os_name, arch):
    """Gets the host platform.

    Args:
        os_name: the host OS name.
        arch: the host arch.
    Returns:
        The host platform.
    """
    host_platform = None
    for platform, meta in PLATFORMS.items():
        if meta.os_name == os_name and meta.arch == arch:
            host_platform = platform
    if not host_platform:
        fail("No platform declared for host OS {} on arch {}".format(os_name, arch))
    return host_platform

def get_host_os_arch(rctx):
    """Infer the host OS name and arch from a repository context.

    Args:
        rctx: Bazel's repository_ctx.
    Returns:
        A tuple with the host OS name and arch.
    """
    os_name = rctx.os.name

    # We assume the arch for Windows is always x86_64.
    if "windows" in os_name.lower():
        arch = "x86_64"

        # Normalize the os_name. E.g. os_name could be "OS windows server 2019".
        os_name = WINDOWS_NAME
    else:
        # This is not ideal, but bazel doesn't directly expose arch.
        arch = repo_utils.execute_unchecked(
            rctx,
            op = "GetUname",
            arguments = [repo_utils.which_checked(rctx, "uname"), "-m"],
        ).stdout.strip()

        # Normalize the os_name.
        if "mac" in os_name.lower():
            os_name = MACOS_NAME
        elif "linux" in os_name.lower():
            os_name = LINUX_NAME

    return (os_name, arch)
