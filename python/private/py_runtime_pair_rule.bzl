# Copyright 2019 The Bazel Authors. All rights reserved.
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

"""Implementation of py_runtime_pair."""

load("@bazel_skylib//rules:common_settings.bzl", "BuildSettingInfo")
load("//python:py_runtime_info.bzl", "PyRuntimeInfo")
load("//python/private/pypi:python_tag.bzl", "python_tag")
load(":common_labels.bzl", "labels")
load(":reexports.bzl", "BuiltinPyRuntimeInfo")

def _get_template_vars(py3_runtime):
    vars = {}
    if py3_runtime.interpreter:
        vars["PYTHON3"] = py3_runtime.interpreter.path
        vars["PYTHON3_ROOTPATH"] = py3_runtime.interpreter.short_path
    elif py3_runtime.interpreter_path:
        vars["PYTHON3"] = py3_runtime.interpreter_path
        vars["PYTHON3_ROOTPATH"] = py3_runtime.interpreter_path

    # BuiltinPyRuntimeInfo (used in Bazel 7) lacks rules_python-specific
    # fields like abi_flags, implementation_name, and
    # interpreter_version_info.
    if hasattr(py3_runtime, "abi_flags"):
        abi_flags = py3_runtime.abi_flags
        vars["PY_ABI_FLAGS"] = abi_flags

        impl_name = py3_runtime.implementation_name
        impl_tag = None
        if impl_name:
            impl_tag = python_tag(impl_name)
            vars["PY_IMPLEMENTATION_NAME"] = impl_name
            vars["PY_WHEEL_IMPLEMENTATION_TAG"] = impl_tag

        version_info = py3_runtime.interpreter_version_info
        if (
            version_info and
            version_info.major != None and
            version_info.minor != None
        ):
            major = str(version_info.major)
            minor = str(version_info.minor)
            major_minor_nodot = "{}{}".format(major, minor)
            vars["PY_MAJOR"] = major
            vars["PY_MINOR"] = minor
            vars["PY_MAJOR_DOT_MINOR"] = "{}.{}".format(major, minor)
            vars["PY_MAJOR_MINOR_NODOT"] = major_minor_nodot
            if impl_tag:
                py_tag = "{}{}".format(impl_tag, major_minor_nodot)
                vars["PY_WHEEL_PYTHON_TAG"] = py_tag
                vars["PY_WHEEL_ABI_TAG"] = "{}{}".format(py_tag, abi_flags)

    return platform_common.TemplateVariableInfo(vars)

def _py_runtime_pair_impl(ctx):
    if ctx.attr.py2_runtime != None:
        py2_runtime = _get_py_runtime_info(ctx.attr.py2_runtime)
        if py2_runtime.python_version != "PY2":
            fail("The Python runtime in the 'py2_runtime' attribute did not have " +
                 "version 'PY2'")
    else:
        py2_runtime = None

    if ctx.attr.py3_runtime != None:
        py3_runtime = _get_py_runtime_info(ctx.attr.py3_runtime)
        if py3_runtime.python_version != "PY3":
            fail("The Python runtime in the 'py3_runtime' attribute did not have " +
                 "version 'PY3'")
    else:
        py3_runtime = None

    if py2_runtime != None:
        fail("Using Python 2 is not supported and disabled; see " +
             "https://github.com/bazelbuild/bazel/issues/15684")

    extra_kwargs = {}
    if ctx.attr._visible_for_testing[BuildSettingInfo].value:
        extra_kwargs["toolchain_label"] = ctx.label

    template_vars = _get_template_vars(py3_runtime)

    return [
        platform_common.ToolchainInfo(
            py2_runtime = py2_runtime,
            py3_runtime = py3_runtime,
            template_vars = template_vars,
            **extra_kwargs
        ),
        template_vars,
    ]

def _get_py_runtime_info(target):
    # Prior to Bazel 7, the builtin PyRuntimeInfo object must be used because
    # py_binary (implemented in Java) performs a type check on the provider
    # value to verify it is an instance of the Java-implemented PyRuntimeInfo
    # class.
    if (PyRuntimeInfo in target) or BuiltinPyRuntimeInfo == None:
        return target[PyRuntimeInfo]
    else:
        return target[BuiltinPyRuntimeInfo]

_MaybeBuiltinPyRuntimeInfo = [[BuiltinPyRuntimeInfo]] if BuiltinPyRuntimeInfo != None else []

py_runtime_pair = rule(
    implementation = _py_runtime_pair_impl,
    attrs = {
        # The two runtimes are used by the py_binary at runtime, and so need to
        # be built for the target platform.
        "py2_runtime": attr.label(
            providers = [[PyRuntimeInfo]] + _MaybeBuiltinPyRuntimeInfo,
            cfg = "target",
            doc = """
The runtime to use for Python 2 targets. Must have `python_version` set to
`PY2`.
""",
        ),
        "py3_runtime": attr.label(
            providers = [[PyRuntimeInfo]] + _MaybeBuiltinPyRuntimeInfo,
            cfg = "target",
            doc = """
The runtime to use for Python 3 targets. Must have `python_version` set to
`PY3`.
""",
        ),
        "_visible_for_testing": attr.label(
            default = labels.VISIBLE_FOR_TESTING,
        ),
    },
    fragments = ["py"],
    doc = """
A toolchain rule for Python.

This wraps up to two Python runtimes, one for Python 2 and one for Python 3.
The rule consuming this toolchain will choose which runtime is appropriate.
Either runtime may be omitted, in which case the resulting toolchain will be
unusable for building Python code using that version.

Usually the wrapped runtimes are declared using the `py_runtime` rule, but any
rule returning a `PyRuntimeInfo` provider may be used.

This rule returns a {obj}`ToolchainInfo` provider with fields:

* `py2_runtime`: {type}`PyRuntimeInfo | None`, runtime information for a
  Python 2 runtime.
* `py3_runtime`: {type}`PyRuntimeInfo | None`, runtime information for a
  Python 3 runtime.
* `template_vars`: {type}`TemplateVariableInfo`, make variables exposed by this
  toolchain.

It also returns a `TemplateVariableInfo` provider with these make variables
(when the corresponding runtime values are set):

* `$(PYTHON3)`: Python 3 interpreter path.
* `$(PYTHON3_ROOTPATH)`: Python 3 interpreter runfiles path.
* `$(PY_ABI_FLAGS)`: Runtime ABI flags (`sys.abiflags`), e.g. `""` or `"t"`.
* `$(PY_IMPLEMENTATION_NAME)`: Implementation name (`sys.implementation.name`),
  e.g. `cpython`.
* `$(PY_MAJOR)`: Major version, e.g. `3`.
* `$(PY_MINOR)`: Minor version, e.g. `12`.
* `$(PY_MAJOR_DOT_MINOR)`: Dotted major and minor version, e.g. `3.12`.
* `$(PY_MAJOR_MINOR_NODOT)`: Dotless major and minor version, e.g. `312`.
* `$(PY_WHEEL_ABI_TAG)`: Wheel ABI tag, e.g. `cp312` or `cp313t`.
* `$(PY_WHEEL_IMPLEMENTATION_TAG)`: Wheel implementation tag, e.g. `cp`.
* `$(PY_WHEEL_PYTHON_TAG)`: Wheel Python tag, e.g. `cp312`.

Example usage:

```python
# In your BUILD file...

load("@rules_python//python:py_runtime.bzl", "py_runtime")
load("@rules_python//python:py_runtime_pair.bzl", "py_runtime_pair")

py_runtime(
    name = "my_py2_runtime",
    interpreter_path = "/system/python2",
    python_version = "PY2",
)

py_runtime(
    name = "my_py3_runtime",
    interpreter_path = "/system/python3",
    python_version = "PY3",
)

py_runtime_pair(
    name = "my_py_runtime_pair",
    py2_runtime = ":my_py2_runtime",
    py3_runtime = ":my_py3_runtime",
)

toolchain(
    name = "my_toolchain",
    target_compatible_with = <...>,
    toolchain = ":my_py_runtime_pair",
    toolchain_type = "@rules_python//python:toolchain_type",
)
```

```python
# In your WORKSPACE...

register_toolchains("//my_pkg:my_toolchain")
```

:::{versionchanged} 2.5.0
Provides `TemplateVariableInfo` and `ToolchainInfo.template_vars`.
:::
""",
)
