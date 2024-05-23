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
"""Providers for Python rules."""

load("@rules_cc//cc:defs.bzl", "CcInfo")
load("//python/private:util.bzl", "IS_BAZEL_6_OR_HIGHER")

DEFAULT_STUB_SHEBANG = "#!/usr/bin/env python3"

DEFAULT_BOOTSTRAP_TEMPLATE = Label("//python/private:python_bootstrap_template.txt")

_PYTHON_VERSION_VALUES = ["PY2", "PY3"]

# Helper to make the provider definitions not crash under Bazel 5.4:
# Bazel 5.4 doesn't support the `init` arg of `provider()`, so we have to
# not pass that when using Bazel 5.4. But, not passing the `init` arg
# changes the return value from a two-tuple to a single value, which then
# breaks Bazel 6+ code.
# This isn't actually used under Bazel 5.4, so just stub out the values
# to get past the loading phase.
def _define_provider(doc, fields, **kwargs):
    if not IS_BAZEL_6_OR_HIGHER:
        return provider("Stub, not used", fields = []), None
    return provider(doc = doc, fields = fields, **kwargs)

def _optional_int(value):
    return int(value) if value != None else None

def interpreter_version_info_struct_from_dict(info_dict):
    """Create a struct of interpreter version info from a dict from an attribute.

    Args:
        info_dict: dict of versio info fields. See interpreter_version_info
            provider field docs.

    Returns:
        struct of version info; see interpreter_version_info provider field docs.
    """
    info_dict = dict(info_dict)  # Copy in case the original is frozen
    if info_dict:
        if not ("major" in info_dict and "minor" in info_dict):
            fail("interpreter_version_info must have at least two keys, 'major' and 'minor'")
    version_info_struct = struct(
        major = _optional_int(info_dict.pop("major", None)),
        minor = _optional_int(info_dict.pop("minor", None)),
        micro = _optional_int(info_dict.pop("micro", None)),
        releaselevel = str(info_dict.pop("releaselevel")) if "releaselevel" in info_dict else None,
        serial = _optional_int(info_dict.pop("serial", None)),
    )

    if len(info_dict.keys()) > 0:
        fail("unexpected keys {} in interpreter_version_info".format(
            str(info_dict.keys()),
        ))

    return version_info_struct

def _PyRuntimeInfo_init(
        *,
        implementation_name = None,
        interpreter_path = None,
        interpreter = None,
        files = None,
        coverage_tool = None,
        coverage_files = None,
        pyc_tag = None,
        python_version,
        stub_shebang = None,
        bootstrap_template = None,
        interpreter_version_info = None):
    if (interpreter_path and interpreter) or (not interpreter_path and not interpreter):
        fail("exactly one of interpreter or interpreter_path must be specified")

    if interpreter_path and files != None:
        fail("cannot specify 'files' if 'interpreter_path' is given")

    if (coverage_tool and not coverage_files) or (not coverage_tool and coverage_files):
        fail(
            "coverage_tool and coverage_files must both be set or neither must be set, " +
            "got coverage_tool={}, coverage_files={}".format(
                coverage_tool,
                coverage_files,
            ),
        )

    if python_version not in _PYTHON_VERSION_VALUES:
        fail("invalid python_version: '{}'; must be one of {}".format(
            python_version,
            _PYTHON_VERSION_VALUES,
        ))

    if files != None and type(files) != type(depset()):
        fail("invalid files: got value of type {}, want depset".format(type(files)))

    if interpreter:
        if files == None:
            files = depset()
    else:
        files = None

    if coverage_files == None:
        coverage_files = depset()

    if not stub_shebang:
        stub_shebang = DEFAULT_STUB_SHEBANG

    return {
        "bootstrap_template": bootstrap_template,
        "coverage_files": coverage_files,
        "coverage_tool": coverage_tool,
        "files": files,
        "implementation_name": implementation_name,
        "interpreter": interpreter,
        "interpreter_path": interpreter_path,
        "interpreter_version_info": interpreter_version_info_struct_from_dict(interpreter_version_info),
        "pyc_tag": pyc_tag,
        "python_version": python_version,
        "stub_shebang": stub_shebang,
    }

# TODO(#15897): Rename this to PyRuntimeInfo when we're ready to replace the Java
# implemented provider with the Starlark one.
PyRuntimeInfo, _unused_raw_py_runtime_info_ctor = _define_provider(
    doc = """Contains information about a Python runtime, as returned by the `py_runtime`
rule.

A Python runtime describes either a *platform runtime* or an *in-build runtime*.
A platform runtime accesses a system-installed interpreter at a known path,
whereas an in-build runtime points to a `File` that acts as the interpreter. In
both cases, an "interpreter" is really any executable binary or wrapper script
that is capable of running a Python script passed on the command line, following
the same conventions as the standard CPython interpreter.
""",
    init = _PyRuntimeInfo_init,
    fields = {
        "bootstrap_template": """
:type: File

See py_runtime_rule.bzl%py_runtime.bootstrap_template for docs.
""",
        "coverage_files": """
:type: depset[File] | None

The files required at runtime for using `coverage_tool`. Will be `None` if no
`coverage_tool` was provided.
""",
        "coverage_tool": """
:type: File | None

If set, this field is a `File` representing tool used for collecting code
coverage information from python tests. Otherwise, this is `None`.
""",
        "files": """
:type: depset[File] | None

If this is an in-build runtime, this field is a `depset` of `File`s that need to
be added to the runfiles of an executable target that uses this runtime (in
particular, files needed by `interpreter`). The value of `interpreter` need not
be included in this field. If this is a platform runtime then this field is
`None`.
""",
        "implementation_name": """
:type: str | None

The Python implementation name (`sys.implementation.name`)
""",
        "interpreter": """
:type: File | None

If this is an in-build runtime, this field is a `File` representing the
interpreter. Otherwise, this is `None`. Note that an in-build runtime can use
either a prebuilt, checked-in interpreter or an interpreter built from source.
""",
        "interpreter_path": """
:type: str | None

If this is a platform runtime, this field is the absolute filesystem path to the
interpreter on the target platform. Otherwise, this is `None`.
""",
        "interpreter_version_info": """
:type: struct

Version information about the interpreter this runtime provides.
It should match the format given by `sys.version_info`, however
for simplicity, the micro, releaselevel, and serial values are
optional.
A struct with the following fields:
* `major`: {type}`int`, the major version number
* `minor`: {type}`int`, the minor version number
* `micro`: {type}`int | None`, the micro version number
* `releaselevel`: {type}`str | None`, the release level
* `serial`: {type}`int | None`, the serial number of the release
""",
        "pyc_tag": """
:type: str | None

The tag portion of a pyc filename, e.g. the `cpython-39` infix
of `foo.cpython-39.pyc`. See PEP 3147. If not specified, it will be computed
from {obj}`implementation_name` and {obj}`interpreter_version_info`. If no
pyc_tag is available, then only source-less pyc generation will function
correctly.
""",
        "python_version": """
:type: str

Indicates whether this runtime uses Python major version 2 or 3. Valid values
are (only) `"PY2"` and `"PY3"`.
""",
        "stub_shebang": """
:type: str

"Shebang" expression prepended to the bootstrapping Python stub
script used when executing {obj}`py_binary` targets.  Does not
apply to Windows.
""",
    },
)

def _check_arg_type(name, required_type, value):
    value_type = type(value)
    if value_type != required_type:
        fail("parameter '{}' got value of type '{}', want '{}'".format(
            name,
            value_type,
            required_type,
        ))

def _PyInfo_init(
        *,
        transitive_sources,
        uses_shared_libraries = False,
        imports = depset(),
        has_py2_only_sources = False,
        has_py3_only_sources = False,
        direct_pyc_files = depset(),
        transitive_pyc_files = depset()):
    _check_arg_type("transitive_sources", "depset", transitive_sources)

    # Verify it's postorder compatible, but retain is original ordering.
    depset(transitive = [transitive_sources], order = "postorder")

    _check_arg_type("uses_shared_libraries", "bool", uses_shared_libraries)
    _check_arg_type("imports", "depset", imports)
    _check_arg_type("has_py2_only_sources", "bool", has_py2_only_sources)
    _check_arg_type("has_py3_only_sources", "bool", has_py3_only_sources)
    _check_arg_type("direct_pyc_files", "depset", direct_pyc_files)
    _check_arg_type("transitive_pyc_files", "depset", transitive_pyc_files)
    return {
        "direct_pyc_files": direct_pyc_files,
        "has_py2_only_sources": has_py2_only_sources,
        "has_py3_only_sources": has_py2_only_sources,
        "imports": imports,
        "transitive_pyc_files": transitive_pyc_files,
        "transitive_sources": transitive_sources,
        "uses_shared_libraries": uses_shared_libraries,
    }

PyInfo, _unused_raw_py_info_ctor = _define_provider(
    doc = "Encapsulates information provided by the Python rules.",
    init = _PyInfo_init,
    fields = {
        "direct_pyc_files": """
:type: depset[File]

Precompiled Python files that are considered directly provided
by the target.
""",
        "has_py2_only_sources": """
:type: bool

Whether any of this target's transitive sources requires a Python 2 runtime.
""",
        "has_py3_only_sources": """
:type: bool

Whether any of this target's transitive sources requires a Python 3 runtime.
""",
        "imports": """\
:type: depset[str]

A depset of import path strings to be added to the `PYTHONPATH` of executable
Python targets. These are accumulated from the transitive `deps`.
The order of the depset is not guaranteed and may be changed in the future. It
is recommended to use `default` order (the default).
""",
        "transitive_pyc_files": """
:type: depset[File]

Direct and transitive precompiled Python files that are provided by the target.
""",
        "transitive_sources": """\
:type: depset[File]

A (`postorder`-compatible) depset of `.py` files appearing in the target's
`srcs` and the `srcs` of the target's transitive `deps`.
""",
        "uses_shared_libraries": """
:type: bool

Whether any of this target's transitive `deps` has a shared library file (such
as a `.so` file).

This field is currently unused in Bazel and may go away in the future.
""",
    },
)

def _PyCcLinkParamsProvider_init(cc_info):
    return {
        "cc_info": CcInfo(linking_context = cc_info.linking_context),
    }

# buildifier: disable=name-conventions
PyCcLinkParamsProvider, _unused_raw_py_cc_link_params_provider_ctor = _define_provider(
    doc = ("Python-wrapper to forward {obj}`CcInfo.linking_context`. This is to " +
           "allow Python targets to propagate C++ linking information, but " +
           "without the Python target appearing to be a valid C++ rule dependency"),
    init = _PyCcLinkParamsProvider_init,
    fields = {
        "cc_info": """
:type: CcInfo

Linking information; it has only {obj}`CcInfo.linking_context` set.
""",
    },
)
