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
load(":which.bzl", "which_with_fail")

def get_repository_name(repository_workspace):
    dummy_label = "//:_"
    return str(repository_workspace.relative(dummy_label))[:-len(dummy_label)] or "@"

def python_toolchain_build_file_content(
        prefix,
        python_version,
        set_python_version_constraint,
        user_repository_name,
        rules_python):
    """Creates the content for toolchain definitions for a build file.

    Args:
        prefix: Python toolchain name prefixes
        python_version: Python versions for the toolchains
        set_python_version_constraint: string, "True" if the toolchain should
            have the Python version constraint added as a requirement for
            matching the toolchain, "False" if not.
        user_repository_name: names for the user repos
        rules_python: rules_python label

    Returns:
        build_content: Text containing toolchain definitions
    """
    if set_python_version_constraint == "True":
        constraint = "{rules_python}//python/config_settings:is_python_{python_version}".format(
            rules_python = rules_python,
            python_version = python_version,
        )
        target_settings = '["{}"]'.format(constraint)
    elif set_python_version_constraint == "False":
        target_settings = "[]"
    else:
        fail(("Invalid set_python_version_constraint value: got {} {}, wanted " +
              "either the string 'True' or the string 'False'; " +
              "(did you convert bool to string?)").format(
            type(set_python_version_constraint),
            repr(set_python_version_constraint),
        ))

    # We create a list of toolchain content from iterating over
    # the enumeration of PLATFORMS.  We enumerate PLATFORMS in
    # order to get us an index to increment the increment.
    return "".join([
        """
toolchain(
    name = "{prefix}{platform}_toolchain",
    target_compatible_with = {compatible_with},
    target_settings = {target_settings},
    toolchain = "@{user_repository_name}_{platform}//:python_runtimes",
    toolchain_type = "@bazel_tools//tools/python:toolchain_type",
)

toolchain(
    name = "{prefix}{platform}_py_cc_toolchain",
    target_compatible_with = {compatible_with},
    target_settings = {target_settings},
    toolchain = "@{user_repository_name}_{platform}//:py_cc_toolchain",
    toolchain_type = "@rules_python//python/cc:toolchain_type",

)
""".format(
            compatible_with = meta.compatible_with,
            platform = platform,
            # We have to use a String value here because bzlmod is passing in a
            # string as we cannot have list of bools in build rule attribues.
            # This if statement does not appear to work unless it is in the
            # toolchain file.
            target_settings = target_settings,
            user_repository_name = user_repository_name,
            prefix = prefix,
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

"""

    # Get the repository name
    rules_python = get_repository_name(rctx.attr._rules_python_workspace)

    toolchains = python_toolchain_build_file_content(
        prefix = "",
        python_version = rctx.attr.python_version,
        set_python_version_constraint = str(rctx.attr.set_python_version_constraint),
        user_repository_name = rctx.attr.user_repository_name,
        rules_python = rules_python,
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
load("@rules_python//python:versions.bzl", "PLATFORMS", "gen_python_config_settings")
gen_python_config_settings()
exports_files(["defs.bzl"])
alias(name = "files",           actual = select({{":" + item: "@{py_repository}_" + item + "//:files" for item in PLATFORMS.keys()}}))
alias(name = "includes",        actual = select({{":" + item: "@{py_repository}_" + item + "//:includes" for item in PLATFORMS.keys()}}))
alias(name = "libpython",       actual = select({{":" + item: "@{py_repository}_" + item + "//:libpython" for item in PLATFORMS.keys()}}))
alias(name = "py3_runtime",     actual = select({{":" + item: "@{py_repository}_" + item + "//:py3_runtime" for item in PLATFORMS.keys()}}))
alias(name = "python_headers",  actual = select({{":" + item: "@{py_repository}_" + item + "//:python_headers" for item in PLATFORMS.keys()}}))
alias(name = "python_runtimes", actual = select({{":" + item: "@{py_repository}_" + item + "//:python_runtimes" for item in PLATFORMS.keys()}}))
alias(name = "python3",         actual = select({{":" + item: "@{py_repository}_" + item + "//:" + ("python.exe" if "windows" in item else "bin/python3") for item in PLATFORMS.keys()}}))
""".format(
        py_repository = rctx.attr.user_repository_name,
    )
    if not is_windows:
        build_contents += """\
alias(name = "pip",             actual = select({{":" + item: "@{py_repository}_" + item + "//:python_runtimes" for item in PLATFORMS.keys() if "windows" not in item}}))
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
    _entry_point = "entry_point",
    _py_binary = "py_binary",
    _py_test = "py_test",
)
load("{rules_python}//python:pip.bzl", _compile_pip_requirements = "compile_pip_requirements")

host_platform = "{host_platform}"
interpreter = "@{py_repository}_{host_platform}//:{python3_binary_path}"

def entry_point(name, **kwargs):
    return _entry_point(
        name = name,
        python_version = "{python_version}",
        **kwargs
    )

def py_binary(name, **kwargs):
    return _py_binary(
        name = name,
        python_version = "{python_version}",
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
    doc = """Creates a repository with a shorter name meant for the host platform, which contains
    a BUILD.bazel file declaring aliases to the host platform's targets.
    """,
    attrs = {
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
    _py_entry_point_binary = "py_entry_point_binary",
    _py_test = "py_test",
)

compile_pip_requirements = _compile_pip_requirements
host_platform = _host_platform
interpreter = _interpreter
py_binary = _py_binary
py_entry_point_binary = _py_entry_point_binary
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
        arch = rctx.execute([which_with_fail("uname", rctx), "-m"]).stdout.strip()

        # Normalize the os_name.
        if "mac" in os_name.lower():
            os_name = MACOS_NAME
        elif "linux" in os_name.lower():
            os_name = LINUX_NAME

    return (os_name, arch)
