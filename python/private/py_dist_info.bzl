"""Implementation of the py_dist_info rule."""

load(":attributes.bzl", "CONFIG_SETTINGS_ATTR", "apply_config_settings_attr")
load(":rule_builders.bzl", "ruleb")
load(":stamp_impl.bzl", "is_stamping_enabled")
load(":toolchain_types.bzl", "TARGET_TOOLCHAIN_TYPE")
load(":transition_labels.bzl", "TRANSITION_LABELS")

PyDistInfo = provider(
    doc = """
Information about `.dist-info` metadata produced by {rule}`py_dist_info_rule`.

:::{versionadded} VERSION_NEXT_FEATURE
:::
""",
    fields = {
        "description_file": """
File | None: Optional file containing the package description.
""",
        "distribution": "str: Name of the distribution.",
        "entry_points_file": """
File | None: Optional generated `entry_points.txt` file.
""",
        "extra_distinfo_files": """
dict[str, File]: Mapping of `.dist-info`-relative filenames to files to include
in the `.dist-info` directory.
""",
        "metadata_file": """
File: Preliminary `metadata.txt` file consumed by `py_wheel`.
""",
        "metadata_inputs": """
depset[File]: Additional input files referenced by `metadata_file` (such as
`requires_file` or `extra_requires_files`).
""",
        "stamping_enabled": """
bool: Whether workspace status stamping is enabled for this distribution
metadata.
""",
        "version": """
str: Version string of the distribution (with Make variables expanded).
""",
    },
)

_PROJECT_URL_LABEL_LENGTH_LIMIT = 32
_DESCRIPTION_FILE_EXTENSION_TO_TYPE = {
    "md": "text/markdown",
    "rst": "text/x-rst",
}
_DEFAULT_DESCRIPTION_FILE_TYPE = "text/plain"

DIST_INFO_ATTR_NAMES = (
    "author",
    "author_email",
    "classifiers",
    "console_scripts",
    "description_content_type",
    "description_file",
    "distribution",
    "entry_points",
    "extra_distinfo_files",
    "extra_requires",
    "extra_requires_files",
    "homepage",
    "license",
    "project_urls",
    "python_requires",
    "requires",
    "requires_file",
    "stamp",
    "summary",
    "version",
)

def replace_make_variables(flag, ctx):
    """Replaces `$(VAR)` Make variables in `flag` using `ctx.var`.

    Args:
        flag: The string in which to expand Make variables.
        ctx: The rule context containing `ctx.var`.

    Returns:
        str: The input string with Make variables expanded.
    """
    if "$" in flag:
        for varname, varsub in ctx.var.items():
            flag = flag.replace("$(%s)" % varname, varsub)
    return flag

def create_dist_info_attrs(*, distribution_mandatory):
    """Creates the attribute dictionary for `.dist-info` metadata.

    Args:
        distribution_mandatory: Whether `distribution` and `version` are
            mandatory attributes on the rule.

    Returns:
        dict[str, attr]: Dictionary of `.dist-info` attributes.
    """
    return {
        "author": attr.string(
            default = "",
            doc = "A string specifying the author of the package.",
        ),
        "author_email": attr.string(
            default = "",
            doc = """
A string specifying the email address of the package author.
""",
        ),
        "classifiers": attr.string_list(
            doc = """
A list of strings describing the categories for the package. For valid
classifiers see <https://pypi.org/classifiers>
""",
        ),
        "console_scripts": attr.string_dict(
            doc = """
Deprecated `console_script` entry points, e.g.
`{'main': 'examples.wheel.main:main'}`.

Deprecated: prefer the `entry_points` attribute, which supports
`console_scripts` as well as other entry points.
""",
        ),
        "description_content_type": attr.string(
            doc = """
The type of contents in `description_file`. If not provided, the type will be
inferred from the extension of `description_file`. Also see
<https://packaging.python.org/en/latest/specifications/core-metadata/#description-content-type>
""",
        ),
        "description_file": attr.label(
            allow_single_file = True,
            doc = "A file containing text describing the package.",
        ),
        "distribution": attr.string(
            mandatory = distribution_mandatory,
            doc = """
Name of the distribution.

This should match the project name on PyPI. It's also the name that is used to
refer to the package in other packages' dependencies.

Workspace status keys are expanded using `{NAME}` format, for example:
 - `distribution = "package.{CLASSIFIER}"`
 - `distribution = "{DISTRIBUTION}"`

For the available keys, see
<https://bazel.build/docs/user-manual#workspace-status>
""",
        ),
        "entry_points": attr.string_list_dict(
            doc = """
`entry_points`, e.g. `{'console_scripts': ['main = examples.wheel.main:main']}`.
""",
        ),
        "extra_distinfo_files": attr.label_keyed_string_dict(
            allow_files = True,
            doc = "Extra files to add to distinfo directory in the archive.",
        ),
        "extra_requires": attr.string_list_dict(
            doc = """
A mapping of [extras](https://peps.python.org/pep-0508/#extras) options to
lists of requirements (similar to `requires`). This attribute is mutually
exclusive with `extra_requires_files`.
""",
        ),
        "extra_requires_files": attr.label_keyed_string_dict(
            allow_files = True,
            doc = """
A mapping of requirements files (similar to `requires_file`) to the name of an
[extras](https://peps.python.org/pep-0508/#extras) option. This attribute is
mutually exclusive with `extra_requires`.
""",
        ),
        "homepage": attr.string(
            default = "",
            doc = "A string specifying the URL for the package homepage.",
        ),
        "license": attr.string(
            default = "",
            doc = "A string specifying the license of the package.",
        ),
        "project_urls": attr.string_dict(
            doc = """
A string dict specifying additional browsable URLs for the project and
corresponding labels, where label is the key and url is the value. e.g
`{{"Bug Tracker": "http://bitbucket.org/tarek/distribute/issues/"}}`
""",
        ),
        "python_requires": attr.string(
            default = "",
            doc = """
Python versions required by this distribution, e.g. '>=3.5,<3.7'.

Supports make variables, e.g. `python_requires = "==$(PY_MAJOR_DOT_MINOR).*"`.
See {rule}`py_runtime_pair` for variables provided by the Python toolchain.

:::{versionchanged} VERSION_NEXT_FEATURE
Supports make variables.
:::
""",
        ),
        "requires": attr.string_list(
            doc = """
List of requirements for this package. See the section on
[Declaring required dependency](https://setuptools.readthedocs.io/en/latest/userguide/dependency_management.html#declaring-dependencies)
for details and examples of the format of this argument. This attribute is
mutually exclusive with `requires_file`.
""",
        ),
        "requires_file": attr.label(
            allow_single_file = True,
            doc = """
A file containing a list of requirements for this package. See the section on
[Declaring required dependency](https://setuptools.readthedocs.io/en/latest/userguide/dependency_management.html#declaring-dependencies)
for details and examples of the format of this argument. This attribute is
mutually exclusive with `requires`.
""",
        ),
        "stamp": attr.int(
            default = -1,
            doc = """
Whether to encode build information into the distribution metadata. Possible
values:

- `stamp = 1`: Always stamp the build information into the wheel, even in
  [--nostamp](https://docs.bazel.build/versions/main/user-manual.html#flag--stamp)
  builds. This setting should be avoided, since it potentially kills remote
  caching for the target and any downstream actions that depend on it.

- `stamp = 0`: Always replace build information by constant values. This gives
  good build result caching.

- `stamp = -1`: Embedding of build information is controlled by the
  [--[no]stamp](https://docs.bazel.build/versions/main/user-manual.html#flag--stamp)
  flag.

Stamped targets are not rebuilt unless their dependencies change.
""",
            values = [1, 0, -1],
        ),
        "summary": attr.string(
            doc = "A one-line summary of what the distribution does",
        ),
        "version": attr.string(
            mandatory = distribution_mandatory,
            doc = """
Version number of the package.

Note that this attribute supports stamp format strings as well as 'make
variables'. For example:
  - `version = "1.2.3-{BUILD_TIMESTAMP}"`
  - `version = "{BUILD_EMBED_LABEL}"`
  - `version = "$(VERSION)"`

Note that Bazel's output filename cannot include the stamp information, as
outputs must be known during the analysis phase and the stamp data is available
only during the action execution.

The [`py_wheel`](#py_wheel) macro produces a `.dist`-suffix target which
creates a `dist/` folder containing the wheel with the stamped name, suitable
for publishing.

See [`py_wheel_dist`](#py_wheel_dist) for more info.
""",
        ),
        "_stamp_flag": attr.label(
            default = Label("//python/private:stamp"),
            doc = """
A setting used to determine whether or not the `--stamp` flag is enabled.
""",
        ),
    }

def _py_dist_info_rule_impl(ctx):
    prefix = ctx.label.name
    distribution = ctx.attr.distribution
    if not distribution:
        fail("`distribution` attribute is required")
    if not ctx.attr.version:
        fail("`version` attribute is required")

    python_requires = replace_make_variables(ctx.attr.python_requires, ctx)
    version_str = replace_make_variables(ctx.attr.version, ctx)

    metadata_inputs = []

    common_metadata_lines = []
    if ctx.attr.author:
        common_metadata_lines.append("Author: %s" % ctx.attr.author)
    if ctx.attr.author_email:
        common_metadata_lines.append("Author-email: %s" % ctx.attr.author_email)
    if ctx.attr.homepage:
        common_metadata_lines.append("Home-page: %s" % ctx.attr.homepage)
    if ctx.attr.license:
        common_metadata_lines.append("License: %s" % ctx.attr.license)
    if ctx.attr.description_content_type:
        common_metadata_lines.append(
            "Description-Content-Type: %s" % ctx.attr.description_content_type,
        )
    elif ctx.attr.description_file:
        description_file_type = _DESCRIPTION_FILE_EXTENSION_TO_TYPE.get(
            ctx.file.description_file.extension,
            _DEFAULT_DESCRIPTION_FILE_TYPE,
        )
        common_metadata_lines.append(
            "Description-Content-Type: %s" % description_file_type,
        )
    if ctx.attr.summary:
        common_metadata_lines.append("Summary: %s" % ctx.attr.summary)

    for label, url in sorted(ctx.attr.project_urls.items()):
        if len(label) > _PROJECT_URL_LABEL_LENGTH_LIMIT:
            fail(
                "`label` {} in `project_urls` is too long. ".format(
                    len(label),
                ) + "It is limited to {} characters.".format(
                    _PROJECT_URL_LABEL_LENGTH_LIMIT,
                ),
            )
        common_metadata_lines.append("Project-URL: %s, %s" % (label, url))

    for c in ctx.attr.classifiers:
        common_metadata_lines.append("Classifier: %s" % c)

    if python_requires:
        common_metadata_lines.append("Requires-Python: %s" % python_requires)

    if ctx.attr.requires and ctx.attr.requires_file:
        fail(
            "`requires` and `requires_file` are mutually exclusive. " +
            "Please update {}".format(ctx.label),
        )

    for req in ctx.attr.requires:
        common_metadata_lines.append("Requires-Dist: %s" % req)

    if ctx.attr.extra_requires and ctx.attr.extra_requires_files:
        fail(
            "`extra_requires` and `extra_requires_files` are mutually " +
            "exclusive. Please update {}".format(ctx.label),
        )

    # Note: Description file and version are not embedded into metadata.txt yet
    # for wheelmaker consumption; wheelmaker normalizes the version, expands @
    # requirement files, and appends the description.
    metadata_file = ctx.actions.declare_file(prefix + ".metadata.txt")
    metadata_contents = [
        "Metadata-Version: 2.1",
        "Name: %s" % distribution,
    ] + common_metadata_lines

    if ctx.attr.requires_file:
        # The @ prefixed paths will be resolved by the PyWheel action,
        # expanding each line containing a constraint in place of this
        # directive.
        metadata_contents.append(
            "Requires-Dist: @%s" % ctx.file.requires_file.path,
        )
        metadata_inputs.append(ctx.file.requires_file)

    extra_requires_lines = []
    for option, option_requirements in sorted(ctx.attr.extra_requires.items()):
        extra_requires_lines.append("Provides-Extra: %s" % option)
        for requirement in option_requirements:
            extra_requires_lines.append(
                "Requires-Dist: %s; extra == '%s'" % (requirement, option),
            )
    metadata_contents.extend(extra_requires_lines)

    extra_requires_files = {}
    for option_target, option in ctx.attr.extra_requires_files.items():
        if option in extra_requires_files:
            fail(
                "Duplicate `extra_requires_files` option '{}' ".format(option) +
                "found on target {}".format(ctx.label),
            )
        option_requires_files = option_target[DefaultInfo].files.to_list()
        if len(option_requires_files) != 1:
            fail(
                "Labels in `extra_requires_files` must result in a single " +
                "file, but {label} provides {files} from {owner}".format(
                    label = ctx.label,
                    files = option_requires_files,
                    owner = option_target.label,
                ),
            )
        extra_requires_files[option] = option_requires_files[0]

    for option, option_requires_file in sorted(extra_requires_files.items()):
        metadata_contents.append("Provides-Extra: %s" % option)
        metadata_contents.append(
            "Requires-Dist: @%s; extra == '%s'" % (
                option_requires_file.path,
                option,
            ),
        )
        metadata_inputs.append(option_requires_file)

    ctx.actions.write(
        output = metadata_file,
        content = "\n".join(metadata_contents) + "\n",
    )

    # Merge console_scripts into entry_points.
    entrypoints = dict(ctx.attr.entry_points)
    if ctx.attr.console_scripts:
        console_scripts = list(entrypoints.get("console_scripts", []))
        entrypoints["console_scripts"] = console_scripts
        for script_name, ref in ctx.attr.console_scripts.items():
            console_scripts.append(
                "{name} = {ref}".format(name = script_name, ref = ref),
            )

    entry_points_file = None
    if entrypoints:
        lines = []
        for group, entries in sorted(entrypoints.items()):
            if lines:
                lines.append("")
            lines.append("[{group}]".format(group = group))
            lines += sorted(entries)
        entry_points_file = ctx.actions.declare_file(
            prefix + "_entry_points.txt",
        )
        ctx.actions.write(
            output = entry_points_file,
            content = "\n".join(lines),
        )

    extra_distinfo_files = {}
    for target, filename in ctx.attr.extra_distinfo_files.items():
        target_files = target[DefaultInfo].files.to_list()
        if len(target_files) != 1:
            fail(
                "Multi-file target listed in extra_distinfo_files %s",
                filename,
            )
        extra_distinfo_files[filename] = target_files[0]

    dist_info = PyDistInfo(
        distribution = distribution,
        version = version_str,
        metadata_file = metadata_file,
        metadata_inputs = depset(metadata_inputs),
        entry_points_file = entry_points_file,
        description_file = ctx.file.description_file,
        extra_distinfo_files = extra_distinfo_files,
        stamping_enabled = is_stamping_enabled(ctx.attr),
    )

    # Write the runtime METADATA file with Version included so
    # importlib.metadata can discover the distribution version in runfiles.
    runtime_metadata_file = ctx.actions.declare_file(prefix + "_METADATA")
    runtime_metadata_lines = (
        [
            "Metadata-Version: 2.1",
            "Name: %s" % dist_info.distribution,
            "Version: %s" % dist_info.version,
        ] +
        common_metadata_lines +
        extra_requires_lines
    )

    ctx.actions.write(
        output = runtime_metadata_file,
        content = "\n".join(runtime_metadata_lines) + "\n",
    )

    # Create runfiles with the .dist-info directory structure
    target_path = ctx.attr.target_path
    path_components = [ctx.label.repo_name or ctx.workspace_name]
    if target_path:
        path_components.append(target_path)
    path_components.append(dist_info.distribution + ".dist-info")
    dist_info_dirname = "/".join(path_components)

    runfiles_files = [runtime_metadata_file]
    root_symlinks = {
        dist_info_dirname + "/METADATA": runtime_metadata_file,
    }
    if dist_info.entry_points_file:
        runfiles_files.append(dist_info.entry_points_file)
        root_symlinks[dist_info_dirname + "/entry_points.txt"] = (
            dist_info.entry_points_file
        )
    for filename, file in dist_info.extra_distinfo_files.items():
        runfiles_files.append(file)
        root_symlinks[dist_info_dirname + "/" + filename] = file

    runfiles = ctx.runfiles(
        files = runfiles_files,
        root_symlinks = root_symlinks,
    )

    return [
        DefaultInfo(
            # We don't set `files` (default outputs) because the files only
            # make sense to show up where the root symlinks put them. Other
            # locations (ones not on sys.path) wouldn't work.
            runfiles = runfiles,
        ),
        dist_info,
    ]

def _transition_dist_info_impl(settings, attr):
    """Transition for py_dist_info."""
    return apply_config_settings_attr(dict(settings), attr)

_py_dist_info_attrs = (
    create_dist_info_attrs(distribution_mandatory = True) |
    CONFIG_SETTINGS_ATTR |
    {
        "target_path": attr.string(
            default = "",
            doc = """
The target path for the `.dist-info` directory, relative to the repository root
in runfiles. If set, this directory must be on `sys.path` (for example via the
`imports` attribute of a `py_library`) for `importlib.metadata` to discover it.
""",
        ),
    }
)

py_dist_info_rule = ruleb.Rule(
    implementation = _py_dist_info_rule_impl,
    doc = """
Generates `.dist-info` package metadata for `importlib.metadata` and `py_wheel`.

This rule generates a `<distribution>.dist-info` directory in the runfiles tree
so Python's `importlib.metadata` can discover package versions, metadata, and
entry points at runtime, and provides {obj}`PyDistInfo` so {obj}`py_wheel` can
reuse the same `.dist-info` definition.

:::{versionadded} VERSION_NEXT_FEATURE
:::
""",
    attrs = _py_dist_info_attrs,
    cfg = transition(
        implementation = _transition_dist_info_impl,
        inputs = TRANSITION_LABELS,
        outputs = TRANSITION_LABELS,
    ),
    provides = [PyDistInfo],
    toolchains = [
        ruleb.ToolchainType(TARGET_TOOLCHAIN_TYPE, mandatory = False),
    ],
).build()

def py_dist_info(**kwargs):
    """Declares Python `.dist-info` package metadata.

    This macro wraps {rule}`py_dist_info_rule` and generates the necessary files
    for Python's `importlib.metadata` to discover package information, including
    versions and entry points, at runtime. Include the `py_dist_info` target in
    the `data` attribute of the corresponding {obj}`py_library`,
    {obj}`py_binary`, or {obj}`py_test`, or pass it via the `dist_info`
    attribute of {obj}`py_wheel`.

    :::{versionadded} VERSION_NEXT_FEATURE
    :::

    Args:
        **kwargs: Rule attributes forwarded to {rule}`py_dist_info_rule`.
    """
    py_dist_info_rule(**kwargs)
