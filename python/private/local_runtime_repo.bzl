# Copyright 2024 The Bazel Authors. All rights reserved.
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

"""Create a repository for a locally installed Python runtime."""

load("//python/private:enum.bzl", "enum")
load(":repo_utils.bzl", "REPO_DEBUG_ENV_VAR", "repo_utils")

# buildifier: disable=name-conventions
_OnFailure = enum(
    SKIP = "skip",
    WARN = "warn",
    FAIL = "fail",
)

_TOOLCHAIN_IMPL_TEMPLATE = """\
# Generated by python/private/local_runtime_repo.bzl

load("@rules_python//python/private:local_runtime_repo_setup.bzl", "define_local_runtime_toolchain_impl")

define_local_runtime_toolchain_impl(
    name = "local_runtime",
    lib_ext = "{lib_ext}",
    major = "{major}",
    minor = "{minor}",
    micro = "{micro}",
    interpreter_path = "{interpreter_path}",
    implementation_name = "{implementation_name}",
    os = "{os}",
)
"""

def _local_runtime_repo_impl(rctx):
    logger = repo_utils.logger(rctx)
    on_failure = rctx.attr.on_failure

    platforms_os_name = repo_utils.get_platforms_os_name(rctx)
    if not platforms_os_name:
        if on_failure == "fail":
            fail("Unrecognized host platform '{}': cannot determine OS constraint".format(
                rctx.os.name,
            ))

        if on_failure == "warn":
            logger.warn(lambda: "Unrecognized host platform '{}': cannot determine OS constraint".format(
                rctx.os.name,
            ))

        # else, on_failure must be skip
        rctx.file("BUILD.bazel", _expand_incompatible_template())
        return

    result = _resolve_interpreter_path(rctx)
    if not result.resolved_path:
        if on_failure == "fail":
            fail("interpreter not found: {}".format(result.describe_failure()))

        if on_failure == "warn":
            logger.warn(lambda: "interpreter not found: {}".format(result.describe_failure()))

        # else, on_failure must be skip
        rctx.file("BUILD.bazel", _expand_incompatible_template())
        return
    else:
        interpreter_path = result.resolved_path

    logger.info(lambda: "resolved interpreter {} to {}".format(rctx.attr.interpreter_path, interpreter_path))

    exec_result = repo_utils.execute_unchecked(
        rctx,
        op = "local_runtime_repo.GetPythonInfo({})".format(rctx.name),
        arguments = [
            interpreter_path,
            rctx.path(rctx.attr._get_local_runtime_info),
        ],
        quiet = True,
    )
    if exec_result.return_code != 0:
        if on_failure == "fail":
            fail("GetPythonInfo failed: {}".format(exec_result.describe_failure()))
        if on_failure == "warn":
            logger.warn(lambda: "GetPythonInfo failed: {}".format(exec_result.describe_failure()))

        # else, on_failure must be skip
        rctx.file("BUILD.bazel", _expand_incompatible_template())
        return

    info = json.decode(exec_result.stdout)
    logger.info(lambda: _format_get_info_result(info))

    # NOTE: Keep in sync with recursive glob in define_local_runtime_toolchain_impl
    repo_utils.watch_tree(rctx, rctx.path(info["include"]))

    # The cc_library.includes values have to be non-absolute paths, otherwise
    # the toolchain will give an error. Work around this error by making them
    # appear as part of this repo.
    rctx.symlink(info["include"], "include")

    # NOTE: For some reason (unknown why), the values found may refer to
    # .a files (static libraries) instead of .so (shared libraries) files.
    shared_lib_names = [
        info["PY3LIBRARY"],  # libpython3.so
        info["LDLIBRARY"],  # libpython3.11.so
        info["INSTSONAME"],  # libpython3.11.so.1.0
    ]

    # In some cases, the value may be empty. Not clear why.
    shared_lib_names = [v for v in shared_lib_names if v]

    # In some cases, the same value is returned or multiple keys. Not clear why.
    shared_lib_names = {v: None for v in shared_lib_names}.keys()

    # It's not entirely clear how to get the directory with libraries.
    # There's several types of libraries with different names and a plethora
    # of settings.
    # https://stackoverflow.com/questions/47423246/get-pythons-lib-path
    # For now, it seems LIBDIR has what is needed, so just use that.
    shared_lib_dir = info["LIBDIR"]

    # The specific files are symlinked instead of the whole directory
    # because it can point to a directory that has more than just
    # the Python runtime shared libraries, e.g. /usr/lib, or a Python
    # specific directory with pip-installed shared libraries.
    rctx.report_progress("Symlinking external Python shared libraries")
    for name in shared_lib_names:
        origin = rctx.path("{}/{}".format(shared_lib_dir, name))

        # The reported names don't always exist; it depends on the particulars
        # of the runtime installation.
        if origin.exists:
            repo_utils.watch(rctx, origin)
            rctx.symlink(origin, "lib/" + name)

    rctx.file("WORKSPACE", "")
    rctx.file("MODULE.bazel", "")
    rctx.file("REPO.bazel", "")
    rctx.file("BUILD.bazel", _TOOLCHAIN_IMPL_TEMPLATE.format(
        major = info["major"],
        minor = info["minor"],
        micro = info["micro"],
        interpreter_path = interpreter_path,
        lib_ext = info["SHLIB_SUFFIX"],
        implementation_name = info["implementation_name"],
        os = "@platforms//os:{}".format(repo_utils.get_platforms_os_name(rctx)),
    ))

local_runtime_repo = repository_rule(
    implementation = _local_runtime_repo_impl,
    doc = """
Use a locally installed Python runtime as a toolchain implementation.

Note this uses the runtime as a *platform runtime*. A platform runtime means
means targets don't include the runtime itself as part of their runfiles or
inputs. Instead, users must assure that where the targets run have the runtime
pre-installed or otherwise available.

This results in lighter weight binaries (in particular, Bazel doesn't have to
create thousands of files for every `py_test`), at the risk of having to rely on
a system having the necessary Python installed.
""",
    attrs = {
        "interpreter_path": attr.string(
            doc = """
An absolute path or program name on the `PATH` env var.

Values with slashes are assumed to be the path to a program. Otherwise, it is
treated as something to search for on `PATH`

Note that, when a plain program name is used, the path to the interpreter is
resolved at repository evalution time, not runtime of any resulting binaries.
""",
            default = "python3",
        ),
        "on_failure": attr.string(
            default = _OnFailure.SKIP,
            values = sorted(_OnFailure.__members__.values()),
            doc = """
How to handle errors when trying to automatically determine settings.

* `skip` will silently skip creating a runtime. Instead, a non-functional
  runtime will be generated and marked as incompatible so it cannot be used.
  This is best if a local runtime is known not to work or be available
  in certain cases and that's OK. e.g., one use windows paths when there
  are people running on linux.
* `warn` will print a warning message. This is useful when you expect
  a runtime to be available, but are OK with it missing and falling back
  to some other runtime.
* `fail` will result in a failure. This is only recommended if you must
  ensure the runtime is available.
""",
        ),
        "_get_local_runtime_info": attr.label(
            allow_single_file = True,
            default = "//python/private:get_local_runtime_info.py",
        ),
        "_rule_name": attr.string(default = "local_runtime_repo"),
    },
    environ = ["PATH", REPO_DEBUG_ENV_VAR],
)

def _expand_incompatible_template():
    return _TOOLCHAIN_IMPL_TEMPLATE.format(
        interpreter_path = "/incompatible",
        implementation_name = "incompatible",
        lib_ext = "incompatible",
        major = "0",
        minor = "0",
        micro = "0",
        os = "@platforms//:incompatible",
    )

def _resolve_interpreter_path(rctx):
    """Find the absolute path for an interpreter.

    Args:
        rctx: A repository_ctx object

    Returns:
        `struct` with the following fields:
        * `resolved_path`: `path` object of a path that exists
        * `describe_failure`: `Callable | None`. If a path that doesn't exist,
          returns a description of why it couldn't be resolved
        A path object or None. The path may not exist.
    """
    if "/" not in rctx.attr.interpreter_path and "\\" not in rctx.attr.interpreter_path:
        # Provide a bit nicer integration with pyenv: recalculate the runtime if the
        # user changes the python version using e.g. `pyenv shell`
        repo_utils.getenv(rctx, "PYENV_VERSION")
        result = repo_utils.which_unchecked(rctx, rctx.attr.interpreter_path)
        resolved_path = result.binary
        describe_failure = result.describe_failure
    else:
        repo_utils.watch(rctx, rctx.attr.interpreter_path)
        resolved_path = rctx.path(rctx.attr.interpreter_path)
        if not resolved_path.exists:
            describe_failure = lambda: "Path not found: {}".format(repr(rctx.attr.interpreter_path))
        else:
            describe_failure = None

    return struct(
        resolved_path = resolved_path,
        describe_failure = describe_failure,
    )

def _format_get_info_result(info):
    lines = ["GetPythonInfo result:"]
    for key, value in sorted(info.items()):
        lines.append("  {}: {}".format(key, value if value != "" else "<empty string>"))
    return "\n".join(lines)
