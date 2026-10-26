"""Implementation of the py_dist_info rule."""

_METADATA_TEMPLATE = """\
Metadata-Version: 2.1
Name: {name}
Version: {version}
"""

def _py_dist_info_rule_impl(ctx):
    package_name = ctx.attr.package_name
    if not package_name:
        fail("package_name attribute is required")
    version = ctx.attr.version
    if not version:
        fail("version attribute is required")

    # Prepare entry_points.txt content
    entry_points_lines = []
    for group, points in ctx.attr.entry_points.items():
        entry_points_lines.append("[%s]" % group)
        entry_points_lines.extend(points)
        entry_points_lines.append("")
    entry_points_content = "\n".join(entry_points_lines)

    # Use unique names for staging files to avoid clashes
    entry_points_staging_file = ctx.actions.declare_file(
        ctx.label.name + "_entry_points.txt",
    )
    ctx.actions.write(entry_points_staging_file, entry_points_content)

    # Prepare METADATA content
    metadata_content = _METADATA_TEMPLATE.format(
        name = package_name,
        version = version,
    )
    metadata_staging_file = ctx.actions.declare_file(
        ctx.label.name + "_METADATA",
    )
    ctx.actions.write(metadata_staging_file, metadata_content)

    # Create runfiles with the .dist-info directory structure
    target_path = ctx.attr.target_path
    path_components = [ctx.label.repo_name or ctx.workspace_name]
    if target_path:
        path_components.append(target_path)
    path_components.append(package_name + ".dist-info")
    dist_info_dirname = "/".join(path_components)

    metadata_symlink_path = dist_info_dirname + "/METADATA"
    entry_points_symlink_path = dist_info_dirname + "/entry_points.txt"

    runfiles = ctx.runfiles(
        files = [entry_points_staging_file, metadata_staging_file],
        root_symlinks = {
            metadata_symlink_path: metadata_staging_file,
            entry_points_symlink_path: entry_points_staging_file,
        },
    )

    return [
        DefaultInfo(
            # We don't set `files` (default outputs) because the files only
            # make sense to show up where the root symlinks put them. Other
            # locations (ones not on sys.path) wouldn't work.
            runfiles = runfiles,
        ),
    ]

py_dist_info_rule = rule(
    implementation = _py_dist_info_rule_impl,
    doc = """
Generates `.dist-info` package metadata in runfiles for `importlib.metadata`.

This rule generates a `<package_name>.dist-info` directory containing `METADATA`
and `entry_points.txt` files in the runfiles tree so Python's
`importlib.metadata` can discover package versions and entry points at runtime.

:::{versionadded} VERSION_NEXT_FEATURE
:::
""",
    attrs = {
        "entry_points": attr.string_list_dict(
            doc = """
A dictionary mapping entry point group names to lists of entry point
specifications (e.g. `{"console_scripts": ["my_cli = my_pkg.cli:main"]}`).
""",
        ),
        "package_name": attr.string(
            mandatory = True,
            doc = """
The distribution package name written to `METADATA` and used for the
`<package_name>.dist-info` directory name.
""",
        ),
        "target_path": attr.string(
            default = "",
            doc = """
The target path for the `.dist-info` directory, relative to the repository root
in runfiles. If set, this directory must be on `sys.path` (for example via the
`imports` attribute of a `py_library`) for `importlib.metadata` to discover it.
""",
        ),
        "version": attr.string(
            mandatory = True,
            doc = """
The distribution package version written to `METADATA`.
""",
        ),
    },
)

def py_dist_info(**kwargs):
    """Declares Python package metadata for `importlib.metadata`.

    This macro wraps {rule}`py_dist_info_rule` and generates the necessary files
    for Python's `importlib.metadata` to discover package information, including
    versions and entry points, at runtime. Include the `py_dist_info` target in
    the `data` attribute of the corresponding {obj}`py_library`,
    {obj}`py_binary`, or {obj}`py_test`.

    :::{versionadded} VERSION_NEXT_FEATURE
    :::

    Args:
        **kwargs: Rule attributes forwarded to {rule}`py_dist_info_rule`.
    """
    py_dist_info_rule(**kwargs)
