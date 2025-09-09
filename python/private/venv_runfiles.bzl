"""Code for constructing venvs."""

load("@bazel_skylib//lib:paths.bzl", "paths")
load(
    ":common.bzl",
    "is_file",
    "relative_path",
    "runfiles_root_path",
)
load(":py_info.bzl", "PyInfo")

def create_venv_app_files(ctx, venv_dir_map):
    """Creates the tree of app-specific files for a venv for a binary.

    App specific files are the files that come from dependencies.

    Args:
        ctx: {type}`ctx` current ctx.
        venv_dir_map: mapping of VenvSymlinkKind constants to the
            venv path. This tells the directory name of
            platform/configuration-dependent directories. The values are
            paths within the current ctx's venv (e.g. `_foo.venv/bin`).

    Returns:
        {type}`list[File}` of the files that were created.
    """

    # maps venv-relative path to the runfiles path it should point to
    entries = depset(
        transitive = [
            dep[PyInfo].venv_symlinks
            for dep in ctx.attr.deps
            if PyInfo in dep
        ],
    ).to_list()

    link_map = build_link_map(ctx, entries)
    venv_files = []
    for kind, kind_map in link_map.items():
        base = venv_dir_map[kind]
        for venv_path, link_to in kind_map.items():
            bin_venv_path = paths.join(base, venv_path)
            if is_file(link_to):
                if link_to.is_directory:
                    venv_link = ctx.actions.declare_directory(bin_venv_path)
                else:
                    venv_link = ctx.actions.declare_file(bin_venv_path)
                ctx.actions.symlink(output = venv_link, target_file = link_to)
            else:
                venv_link = ctx.actions.declare_symlink(bin_venv_path)
                venv_link_rf_path = runfiles_root_path(ctx, venv_link.short_path)
                rel_path = relative_path(
                    # dirname is necessary because a relative symlink is relative to
                    # the directory the symlink resides within.
                    from_ = paths.dirname(venv_link_rf_path),
                    to = link_to,
                )
                ctx.actions.symlink(output = venv_link, target_path = rel_path)
            venv_files.append(venv_link)

    return venv_files

# Visible for testing
def build_link_map(ctx, entries):
    """Compute the mapping of venv paths to their backing objects.


    Args:
        ctx: {type}`ctx` current ctx.
        entries: {type}`list[VenvSymlinkEntry]` the entries that describe the
            venv-relative

    Returns:
        {type}`dict[str, dict[str, str|File]]` Mappings of venv paths to their
        backing files. The first key is a `VenvSymlinkKind` value.
        The inner dict keys are venv paths relative to the kind's diretory. The
        inner dict values are strings or Files to link to.
    """

    version_by_pkg = {}  # dict[str pkg, str version]
    entries_by_kind = {}  # dict[str kind, list[entry]]

    # Group by path kind and reduce to a single package's version of entries
    for entry in entries:
        entries_by_kind.setdefault(entry.kind, [])
        if not entry.package:
            entries_by_kind[entry.kind].append(entry)
            continue
        if entry.package not in version_by_pkg:
            version_by_pkg[entry.package] = entry.version
            entries_by_kind[entry.kind].append(entry)
            continue
        if entry.version == version_by_pkg[entry.package]:
            entries_by_kind[entry.kind].append(entry)
            continue

        # else: ignore it; not the selected version

    # final paths to keep, grouped by kind
    keep_link_map = {}  # dict[str kind, dict[path, str|File]]
    for kind, entries in entries_by_kind.items():
        # dict[str kind-relative path, str|File link_to]
        keep_kind_link_map = {}

        groups = _group_venv_path_entries(entries)

        for group in groups:
            # If there's just one group, we can symlink to the directory
            if len(group) == 1:
                entry = group[0]
                keep_kind_link_map[entry.venv_path] = entry.link_to_path
            else:
                # Merge a group of overlapping prefixes
                _merge_venv_path_group(ctx, group, keep_kind_link_map)

        keep_link_map[kind] = keep_kind_link_map

    return keep_link_map

def _group_venv_path_entries(entries):
    """Group entries by VenvSymlinkEntry.venv_path overlap.

    This does an initial grouping by the top-level venv path an entry wants.
    Entries that are underneath another entry are put into the same group.

    Returns:
        {type}`list[list[VenvSymlinkEntry]]` The inner list is the entries under
        a common venv path. The inner list is ordered from shortest to longest
        path.
    """

    # Sort so order is top-down, ensuring grouping by short common prefix
    entries = sorted(entries, key = lambda e: e.venv_path)

    groups = []
    current_group = None
    current_group_prefix = None
    for entry in entries:
        prefix = entry.venv_path
        anchored_prefix = prefix + "/"
        if (current_group_prefix == None or
            not anchored_prefix.startswith(current_group_prefix)):
            current_group_prefix = anchored_prefix
            current_group = [entry]
            groups.append(current_group)
        else:
            current_group.append(entry)

    return groups

def _merge_venv_path_group(ctx, group, keep_map):
    """Merges a group of overlapping prefixes.

    Args:
        ctx: {type}`ctx` current ctx.
        group: {type}`dict[str, VenvSymlinkEntry]` map of prefixes and their
            values. Keys are the venv kind relative prefix.
        keep_map: {type}`dict[str, str|File]` files kept after merging are
            populated into this map.
    """

    # TODO: Compute the minimum number of entries to create. This can't avoid
    # flattening the files depset, but can lower the number of materialized
    # files significantly. Usually overlaps are limited to a small number
    # of directories.
    for entry in group:
        prefix = entry.venv_path
        for file in entry.files.to_list():
            # Compute the file-specific venv path. i.e. the relative
            # path of the file under entry.venv_path, joined with
            # entry.venv_path
            rf_root_path = runfiles_root_path(ctx, file.short_path)
            if not rf_root_path.startswith(entry.link_to_path):
                # This generally shouldn't occur in practice, but just
                # in case, skip them, for lack of a better option.
                continue
            venv_path = "{}/{}".format(
                prefix,
                rf_root_path.removeprefix(entry.link_to_path + "/"),
            )

            # For lack of a better option, first added wins. We happen to
            # go in top-down prefix order, so the highest level namespace
            # package typically wins.
            if venv_path not in keep_map:
                keep_map[venv_path] = file
