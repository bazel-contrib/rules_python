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

"Implementation of py_wheel rule"

load(":attributes.bzl", "CONFIG_SETTINGS_ATTR", "apply_config_settings_attr")
load(
    ":py_dist_info.bzl",
    "DIST_INFO_ATTR_NAMES",
    "PyDistInfo",
    "create_dist_info_attrs",
    "replace_make_variables",
)
load(":py_info.bzl", "PyInfo")
load(":py_package.bzl", "py_package_lib")
load(":rule_builders.bzl", "ruleb")
load(":toolchain_types.bzl", "TARGET_TOOLCHAIN_TYPE")
load(":transition_labels.bzl", "TRANSITION_LABELS")
load(":version.bzl", "version")

PyWheelInfo = provider(
    doc = "Information about a wheel produced by `py_wheel`",
    fields = {
        "name_file": (
            "File: A file containing the canonical name of the wheel (after " +
            "stamping, if enabled)."
        ),
        "wheel": "File: The wheel file itself.",
    },
)

ALLOWED_DATA_FILE_PREFIX = ("purelib", "platlib", "headers", "scripts", "data")

_wheel_only_attrs = {
    "abi": attr.string(
        default = "none",
        doc = """
Python ABI tag. 'none' for pure-Python wheels.

Supports make variables, e.g. `abi = "$(PY_WHEEL_ABI_TAG)"`. See
{rule}`py_runtime_pair` for variables provided by the Python toolchain.

:::{versionchanged} VERSION_NEXT_FEATURE
Python toolchain make variables (such as `$(PY_WHEEL_ABI_TAG)`) are available by
default.
:::
""",
    ),
    "add_path_prefix": attr.string(
        default = "",
        doc = """\
Path prefix to prepend to files added to the generated package.
This prefix will be prepended **after** the paths are first stripped of the prefixes
specified in `strip_path_prefixes`.

For example:
+ `"foo/" will prepend to `"bar/baz/file.py"` as `"foo/bar/baz/file.py"`
+ `"foo_" will prepend to `"bar/baz/file.py"` as `"foo_bar/baz/file.py"`
+ `stripping ["bar/"] and adding "foo/" will change `"bar/baz/file.py"` to `"foo/baz/file.py"`

:::{versionadded} 2.0.0
The {attr}`add_path_prefix` attribute was added.
:::
""",
    ),
    "compress": attr.bool(
        default = True,
        doc = "Enable compression of the final archive.",
    ),
    "data_files": attr.label_keyed_string_dict(
        doc = ("""
Mapping of data files to go into the wheel.

The keys are targets of files to include, and the values are the `.data`-relative
path to use.

Any file that is not normally installed inside site-packages goes into the .data
directory, named as the .dist-info directory but with the .data/ extension. If
the destination of a file or group of files ends in a `/`, the destination is a
folder and files are placed with their existing basenames under that folder.

For example:

```
":file1.txt": "data/file1.txt",   # Destination: <wheelname>.data/data/file1.txt
":file1.txt": "data/",            # Destination: <wheelname>.data/data/file1.txt
":file1.txt": "data/special.txt", # Destination: <wheelname>.data/data/special.txt

filegroup(name = "files", srcs = [":file1.txt", ":file2.txt"])
":files": "data/",                # Destinations: <wheelname>.data/data/file1.txt, <wheelname>.data/data/file2.txt
```

Allowed paths: {prefixes}

:::{{versionchanged}} 2.0.0
Values can end in slash (`/`) to indicate that all files of the target should
be moved under that directory.
:::
""".format(prefixes = ALLOWED_DATA_FILE_PREFIX)),
        allow_files = True,
    ),
    "deps": attr.label_list(
        doc = """
Targets to be included in the distribution.

The targets to package are usually `py_library` rules or filesets (for
packaging data files).

Note it's usually better to package `py_library` targets and use
`entry_points` attribute to specify `console_scripts` than to package
`py_binary` rules. `py_binary` targets would wrap a executable script that
tries to locate `.runfiles` directory which is not packaged in the wheel.
""",
    ),
    "dist_info": attr.label(
        doc = """
A {obj}`py_dist_info` target providing `.dist-info` metadata for the wheel.

If not provided, the `py_wheel` macro automatically constructs a `py_dist_info`
target from the distribution metadata attributes passed to `py_wheel`.
If `dist_info` is specified, passing any of the distribution metadata attributes
directly to `py_wheel` is an error.

:::{versionadded} VERSION_NEXT_FEATURE
:::
""",
        providers = [PyDistInfo],
    ),
    "platform": attr.string(
        default = "any",
        doc = """
Supported platform. Use 'any' for pure-Python wheel.

If you have included platform-specific data, such as a .pyd or .so
extension module, you will need to specify the platform in standard
pip format. If you support multiple platforms, you can define
platform constraints, then use a select() to specify the appropriate
specifier, eg:

`
platform = select({
    "//platforms:windows_x86_64": "win_amd64",
    "//platforms:macos_x86_64": "macosx_10_7_x86_64",
    "//platforms:linux_x86_64": "manylinux2014_x86_64",
})
`

Supports make variables.

:::{versionchanged} VERSION_NEXT_FEATURE
Supports make variables.
:::
""",
    ),
    "python_tag": attr.string(
        default = "py3",
        doc = """
Supported Python version(s), eg `py3`, `cp35.cp36`, etc.

Supports make variables, e.g. `python_tag = "$(PY_WHEEL_PYTHON_TAG)"`. See
{rule}`py_runtime_pair` for variables provided by the Python toolchain.

:::{versionchanged} VERSION_NEXT_FEATURE
Python toolchain make variables (such as `$(PY_WHEEL_PYTHON_TAG)`) are available
by default.
:::
""",
    ),
    "strip_path_prefixes": attr.string_list(
        default = [],
        doc = """\
Path prefixes to strip from files added to the generated package.
Prefixes are checked **in order** and only the **first match** will be used.

For example:
+ `["foo", "foo/bar/baz"]` will strip `"foo/bar/baz/file.py"` to `"bar/baz/file.py"`
+ `["foo/bar/baz", "foo"]` will strip `"foo/bar/baz/file.py"` to `"file.py"` and
  `"foo/file2.py"` to `"file2.py"`
""",
    ),
    "_wheelmaker": attr.label(
        executable = True,
        cfg = "exec",
        default = "//tools:wheelmaker",
    ),
}

def _escape_filename_distribution_name(name):
    """Escape the distribution name component of a filename.

    See https://packaging.python.org/en/latest/specifications/binary-distribution-format/#escaping-and-unicode
    and https://packaging.python.org/en/latest/specifications/name-normalization/.

    Apart from the valid names according to the above, we also accept
    '{' and '}', which may be used as placeholders for stamping.
    """
    escaped = ""
    _inside_stamp_var = False
    for character in name.elems():
        if character == "{":
            _inside_stamp_var = True
            escaped += character
        elif character == "}":
            _inside_stamp_var = False
            escaped += character
        elif character.isalnum():
            escaped += character if _inside_stamp_var else character.lower()
        elif character in ["-", "_", "."]:
            if escaped == "":
                fail(
                    "A valid name must start with a letter or number.",
                    "Name '%s' does not." % name,
                )
            elif escaped.endswith("_"):
                pass
            else:
                escaped += "_"
        else:
            fail(
                "A valid name consists only of ASCII letters ",
                "and numbers, period, underscore and hyphen.",
                "Name '%s' has bad character '%s'." % (name, character),
            )
    if escaped.endswith("_"):
        fail(
            "A valid name must end with a letter or number.",
            "Name '%s' does not." % name,
        )
    return escaped

def _escape_filename_segment(segment):
    """Escape a segment of the wheel filename.

    See {pep}`PEP 427`
    """

    # TODO: this is wrong, isalnum replaces non-ascii letters, while we should
    # not replace them.
    # TODO: replace this with a regexp once starlark supports them.
    escaped = ""
    for character in segment.elems():
        # isalnum doesn't handle unicode characters properly.
        if character.isalnum() or character == ".":
            escaped += character
        elif not escaped.endswith("_"):
            escaped += "_"
    return escaped

def _input_file_to_arg(input_file):
    """Converts a File object to string for --input_file argument to wheelmaker"""
    return "%s;%s" % (py_package_lib.path_inside_wheel(input_file), input_file.path)

def _has_dist_info_attr(ctx, attr_name):
    value = getattr(ctx.attr, attr_name)
    if attr_name == "stamp":
        return value != -1
    return bool(value)

def _py_wheel_impl(ctx):
    if not ctx.attr.dist_info:
        fail("`dist_info` attribute is required on {}".format(ctx.label))

    # If the user passed `dist_info` explicitly rather than using the implicit
    # `<name>.dist_info` target created by the `py_wheel` macro, reject any
    # direct `.dist-info` metadata attributes on `py_wheel`.
    implicit_dist_info_name = ctx.label.name + ".dist_info"
    is_implicit_dist_info = (
        ctx.attr.dist_info.label.package == ctx.label.package and
        ctx.attr.dist_info.label.name == implicit_dist_info_name
    )
    if not is_implicit_dist_info:
        conflicting_attrs = [
            attr_name
            for attr_name in DIST_INFO_ATTR_NAMES
            if _has_dist_info_attr(ctx, attr_name)
        ]
        if conflicting_attrs:
            fail(
                "Cannot specify {} together with `dist_info` on {}".format(
                    ", ".join(["`{}`".format(a) for a in conflicting_attrs]),
                    ctx.label,
                ),
            )

    dist_info = ctx.attr.dist_info[PyDistInfo]
    abi = replace_make_variables(ctx.attr.abi, ctx)
    platform = replace_make_variables(ctx.attr.platform, ctx)
    python_tag = replace_make_variables(ctx.attr.python_tag, ctx)
    distribution = dist_info.distribution
    version_str = dist_info.version

    filename_segments = [
        _escape_filename_distribution_name(distribution),
        version.normalize(version_str),
        _escape_filename_segment(python_tag),
        _escape_filename_segment(abi),
        _escape_filename_segment(platform),
    ]

    outfile = ctx.actions.declare_file("-".join(filename_segments) + ".whl")

    name_file = ctx.actions.declare_file(ctx.label.name + ".name")

    direct_pyi_files = []
    for dep in ctx.attr.deps:
        if PyInfo in dep:
            direct_pyi_files.extend(dep[PyInfo].direct_pyi_files.to_list())

    inputs_to_package = depset(
        direct = ctx.files.deps + direct_pyi_files,
    )

    other_inputs = []

    # Wrap the inputs into a file to reduce command line length, deferring
    # depset expansion to execution time via Args.add_all with map_each.
    packageinputfile = ctx.actions.declare_file(
        ctx.attr.name + "_target_wrapped_inputs.txt",
    )
    package_args = ctx.actions.args()
    package_args.set_param_file_format("multiline")
    package_args.add_all(inputs_to_package, map_each = _input_file_to_arg)
    ctx.actions.write(output = packageinputfile, content = package_args)
    other_inputs.append(packageinputfile)

    args = ctx.actions.args()
    args.add("--name", distribution)
    args.add("--version", version_str)
    args.add("--python_tag", python_tag)
    args.add("--abi", abi)
    args.add("--platform", platform)
    args.add("--out", outfile)
    args.add("--name_file", name_file)
    args.add_all(
        ctx.attr.strip_path_prefixes,
        format_each = "--strip_path_prefix=%s",
    )
    args.add("--path_prefix", ctx.attr.add_path_prefix)

    # Pass workspace status files if stamping is enabled
    if dist_info.stamping_enabled:
        args.add("--volatile_status_file", ctx.version_file)
        args.add("--stable_status_file", ctx.info_file)
        other_inputs.extend([ctx.version_file, ctx.info_file])

    args.add("--input_file_list", packageinputfile)

    other_inputs.append(dist_info.metadata_file)
    args.add("--metadata_file", dist_info.metadata_file)

    if dist_info.entry_points_file:
        other_inputs.append(dist_info.entry_points_file)
        args.add("--entry_points_file", dist_info.entry_points_file)

    if dist_info.description_file:
        args.add("--description_file", dist_info.description_file)
        other_inputs.append(dist_info.description_file)

    if not ctx.attr.compress:
        args.add("--no_compress")

    for filename, file in dist_info.extra_distinfo_files.items():
        other_inputs.append(file)
        args.add(
            "--extra_distinfo_file",
            filename + ";" + file.path,
        )

    for target, filename in ctx.attr.data_files.items():
        target_files = target[DefaultInfo].files.to_list()
        if len(target_files) != 1 and not filename.endswith("/"):
            fail(
                "Multi-file target listed in data_files %s, this is only supported when specifying a folder path (i.e. a path ending in '/')",
                filename,
            )

        if filename.partition("/")[0] not in ALLOWED_DATA_FILE_PREFIX:
            fail(
                "The target data file must start with one of these prefixes: '%s'.  Target filepath: '%s'" %
                (
                    ",".join(ALLOWED_DATA_FILE_PREFIX),
                    filename,
                ),
            )

        for file in target_files:
            final_filename = filename + file.basename if filename.endswith("/") else filename

            other_inputs.extend(target_files)
            args.add(
                "--data_files",
                final_filename + ";" + file.path,
            )

    ctx.actions.run(
        mnemonic = "PyWheel",
        inputs = depset(
            direct = other_inputs,
            transitive = [inputs_to_package, dist_info.metadata_inputs],
        ),
        outputs = [outfile, name_file],
        arguments = [args],
        executable = ctx.executable._wheelmaker,
        # The default shell env is used to better support toolchains that look
        # up python at runtime using PATH.
        use_default_shell_env = True,
        progress_message = "Building wheel {}".format(ctx.label),
    )
    return [
        DefaultInfo(
            files = depset([outfile]),
            runfiles = ctx.runfiles(files = [outfile]),
        ),
        PyWheelInfo(
            wheel = outfile,
            name_file = name_file,
        ),
    ]

py_wheel_lib = struct(
    implementation = _py_wheel_impl,
    attrs = (
        _wheel_only_attrs |
        create_dist_info_attrs(distribution_mandatory = False) |
        CONFIG_SETTINGS_ATTR
    ),
)

def _transition_wheel_impl(settings, attr):
    """Transition for py_wheel."""
    return apply_config_settings_attr(dict(settings), attr)

py_wheel = ruleb.Rule(
    implementation = py_wheel_lib.implementation,
    doc = """
Internal rule used by the [py_wheel macro](#py_wheel).

These intentionally have the same name to avoid sharp edges with Bazel macros.
For example, a `bazel query` for a user's `py_wheel` macro expands to `py_wheel` targets,
in the way they expect.
""",
    attrs = py_wheel_lib.attrs,
    cfg = transition(
        implementation = _transition_wheel_impl,
        inputs = TRANSITION_LABELS,
        outputs = TRANSITION_LABELS,
    ),
    toolchains = [
        ruleb.ToolchainType(TARGET_TOOLCHAIN_TYPE, mandatory = False),
    ],
).build()
