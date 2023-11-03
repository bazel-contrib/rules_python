# Copyright 2023 The Bazel Authors. All rights reserved.
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

"""Rules to verify and update pip-compile locked requirements.txt"""

load("//python:defs.bzl", _py_binary = "py_binary", _py_test = "py_test")
load("//python/pip_install:repositories.bzl", "requirement")

def compile_pip_requirements(
        name,
        srcs = None,
        extra_args = [],
        extra_deps = [],
        generate_hashes = True,
        py_binary = _py_binary,
        py_test = _py_test,
        requirements_in = None,
        requirements_txt = None,
        requirements_darwin = None,
        requirements_linux = None,
        requirements_windows = None,
        visibility = ["//visibility:private"],
        tags = None,
        **kwargs):
    """Generates targets for managing pip dependencies with pip-compile.

    By default this rules generates a filegroup named "[name]" which can be included in the data
    of some other compile_pip_requirements rule that references these requirements
    (e.g. with `-r ../other/requirements.txt`).

    It also generates two targets for running pip-compile:

    - validate with `bazel test [name]_test`
    - update with   `bazel run [name].update`

    If you are using a version control system, the requirements.txt generated by this rule should
    be checked into it to ensure that all developers/users have the same dependency versions.

    Args:
        name: base name for generated targets, typically "requirements".
        srcs: list of files containing inputs to dependency resolution. If not specified,
            defaults to `["pyproject.toml"]`. Supported formats are:
            * a requirements text file, usually named `requirements.in`
            * A `pyproject.toml` file, where the `project.dependencies` list is used as per
              [PEP621](https://peps.python.org/pep-0621/).
        extra_args: passed to pip-compile.
        extra_deps: extra dependencies passed to pip-compile.
        generate_hashes: whether to put hashes in the requirements_txt file.
        py_binary: the py_binary rule to be used.
        py_test: the py_test rule to be used.
        requirements_in: file expressing desired dependencies. Deprecated, use srcs instead.
        requirements_txt: result of "compiling" the requirements.in file.
        requirements_linux: File of linux specific resolve output to check validate if requirement.in has changes.
        requirements_darwin: File of darwin specific resolve output to check validate if requirement.in has changes.
        requirements_windows: File of windows specific resolve output to check validate if requirement.in has changes.
        tags: tagging attribute common to all build rules, passed to both the _test and .update rules.
        visibility: passed to both the _test and .update rules.
        **kwargs: other bazel attributes passed to the "_test" rule.
    """
    if requirements_in and srcs:
        fail("Only one of 'srcs' and 'requirements_in' attributes can be used")

    if requirements_in:
        srcs = [requirements_in]
    else:
        srcs = srcs or ["pyproject.toml"]

    requirements_txt = name + ".txt" if requirements_txt == None else requirements_txt

    # "Default" target produced by this macro
    # Allow a compile_pip_requirements rule to include another one in the data
    # for a requirements file that does `-r ../other/requirements.txt`
    native.filegroup(
        name = name,
        srcs = kwargs.pop("data", []) + [requirements_txt],
        visibility = visibility,
    )

    data = [name, requirements_txt] + srcs + [f for f in (requirements_linux, requirements_darwin, requirements_windows) if f != None]

    # Use the Label constructor so this is expanded in the context of the file
    # where it appears, which is to say, in @rules_python
    pip_compile = Label("//python/pip_install/tools/dependency_resolver:dependency_resolver.py")

    loc = "$(rlocationpath {})"

    args = ["--src={}".format(loc.format(src)) for src in srcs] + [
        loc.format(requirements_txt),
        "//%s:%s.update" % (native.package_name(), name),
        "--resolver=backtracking",
        "--allow-unsafe",
    ]
    if generate_hashes:
        args.append("--generate-hashes")
    if requirements_linux:
        args.append("--requirements-linux={}".format(loc.format(requirements_linux)))
    if requirements_darwin:
        args.append("--requirements-darwin={}".format(loc.format(requirements_darwin)))
    if requirements_windows:
        args.append("--requirements-windows={}".format(loc.format(requirements_windows)))
    args.extend(extra_args)

    deps = [
        requirement("build"),
        requirement("click"),
        requirement("colorama"),
        requirement("importlib_metadata"),
        requirement("more_itertools"),
        requirement("packaging"),
        requirement("pep517"),
        requirement("pip"),
        requirement("pip_tools"),
        requirement("pyproject_hooks"),
        requirement("setuptools"),
        requirement("tomli"),
        requirement("zipp"),
        Label("//python/runfiles:runfiles"),
    ] + extra_deps

    tags = tags or []
    tags.append("requires-network")
    tags.append("no-remote-exec")
    tags.append("no-sandbox")
    attrs = {
        "args": args,
        "data": data,
        "deps": deps,
        "main": pip_compile,
        "srcs": [pip_compile],
        "tags": tags,
        "visibility": visibility,
    }

    # cheap way to detect the bazel version
    _bazel_version_4_or_greater = "propeller_optimize" in dir(native)

    # Bazel 4.0 added the "env" attribute to py_test/py_binary
    if _bazel_version_4_or_greater:
        attrs["env"] = kwargs.pop("env", {})

    py_binary(
        name = name + ".update",
        **attrs
    )

    timeout = kwargs.pop("timeout", "short")

    py_test(
        name = name + "_test",
        timeout = timeout,
        # kwargs could contain test-specific attributes like size or timeout
        **dict(attrs, **kwargs)
    )
