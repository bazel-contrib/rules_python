"""Code for constructing venvs."""

load("@bazel_skylib//lib:paths.bzl", "paths")
load(
    ":common.bzl",
    "PYTHON_FILE_EXTENSIONS",
    "is_file",
    "relative_path",
    "runfiles_root_path",
)
load(
    ":py_info.bzl",
    "PyInfo",
    "VenvSymlinkEntry",
    "VenvSymlinkKind",
)

def create_venv_app_files(ctx, deps, venv_dir_map):
    """Creates the tree of app-specific files for a venv for a binary.

    App specific files are the files that come from dependencies.

    Args:
        ctx: {type}`ctx` current ctx.
        deps: {type}`list[Target]` the targets whose venv information
            to put into the returned venv files.
        venv_dir_map: mapping of VenvSymlinkKind constants to the
            venv path. This tells the directory name of
            platform/configuration-dependent directories. The values are
            paths within the current ctx's venv (e.g. `_foo.venv/bin`).

    Returns:
        {type}`struct` with the following attributes:
        * {type}`list[File]` `venv_files` additional files created for
          the venv.
        * {type}`dict[str, File]` `runfiles_symlinks` map intended for
          the `runfiles.symlinks` argument. A map of main-repo
          relative paths to File.
    """

    # maps venv-relative path to the runfiles path it should point to
    entries = depset(
        transitive = [
            dep[PyInfo].venv_symlinks
            for dep in deps
            if PyInfo in dep
        ],
    ).to_list()

    link_map = build_link_map(ctx, entries)
    venv_files = []
    runfiles_symlinks = {}

    for kind, kind_map in link_map.items():
        base = venv_dir_map[kind]
        for venv_path, link_to in kind_map.items():
            bin_venv_path = paths.join(base, venv_path)
            if is_file(link_to):
                symlink_from = "{}/{}".format(ctx.label.package, bin_venv_path)
                runfiles_symlinks[symlink_from] = link_to

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

    return struct(
        venv_files = venv_files,
        runfiles_symlinks = runfiles_symlinks,
    )

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
        The inner dict keys are venv paths relative to the kind's directory. The
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
                if entry.link_to_file:
                    keep_kind_link_map[entry.venv_path] = entry.link_to_file
                else:
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
    # Split it into path components so `foo foo-bar foo/bar` sorts as
    # `foo foo/bar foo-bar`
    entries = sorted(entries, key = lambda e: tuple(e.venv_path.split("/")))

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
        group: {type}`list[VenvSymlinkEntry]` a group of entries with overlapping
            `venv_path` prefixes, ordered from shortest to longest path.
        keep_map: {type}`dict[str, str|File]` files kept after merging are
            populated into this map.
    """

    # TODO: Compute the minimum number of entries to create. This can't avoid
    # flattening the files depset, but can lower the number of materialized
    # files significantly. Usually overlaps are limited to a small number
    # of directories. Note that, when doing so, shared libraries need to
    # be symlinked directly, not the directory containing them, due to
    # dynamic linker symlink resolution semantics on Linux.
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

def get_venv_symlinks(ctx, files, package, version_str, site_packages_root):
    """Compute the VenvSymlinkEntry objects for a library.

    Args:
        ctx: {type}`ctx` the current ctx.
        files: {type}`list[File]` the underlying files that are under
            `site_packages_root` and intended to be part of the venv
            contents.
        package: {type}`str` the Python distribution name.
        version_str: {type}`str` the distribution's version.
        site_packages_root: {type}`str` prefix under which files are
            considered to be part of the installed files.

    Returns:
        {type}`list[VenvSymlinkEntry]` the entries that describe how
        to map the files into a venv.
    """
    if site_packages_root.endswith("/"):
        fail("The `site_packages_root` value cannot end in " +
             "slash, got {}".format(site_packages_root))
    if site_packages_root.startswith("/"):
        fail("The `site_packages_root` cannot start with " +
             "slash, got {}".format(site_packages_root))

    # Append slash to prevent incorrect prefix-string matches
    site_packages_root += "/"

    # We have to build a list of (runfiles path, site-packages path) pairs of the files to
    # create in the consuming binary's venv site-packages directory. To minimize the number of
    # files to create, we just return the paths to the directories containing the code of
    # interest.
    #
    # However, namespace packages complicate matters: multiple distributions install in the
    # same directory in site-packages. This works out because they don't overlap in their
    # files. Typically, they install to different directories within the namespace package
    # directory. We also need to ensure that we can handle a case where the main package (e.g.
    # airflow) has directories only containing data files and then namespace packages coming
    # along and being next to it.
    #
    # Lastly we have to assume python modules just being `.py` files (e.g. typing-extensions)
    # is just a single Python file.

    dir_symlinks = {}  # dirname -> runfile path
    venv_symlinks = []

    # Sort so order is top-down
    all_files = sorted(files, key = lambda f: f.short_path)

    for src in all_files:
        path = _repo_relative_short_path(src.short_path)
        if not path.startswith(site_packages_root):
            continue
        path = path.removeprefix(site_packages_root)
        dir_name, _, filename = path.rpartition("/")
        runfiles_dir_name, _, _ = runfiles_root_path(ctx, src.short_path).partition("/")

        if _is_linker_loaded_library(filename):
            entry = VenvSymlinkEntry(
                kind = VenvSymlinkKind.LIB,
                link_to_path = paths.join(runfiles_dir_name, site_packages_root, filename),
                link_to_file = src,
                package = package,
                version = version_str,
                venv_path = path,
                files = depset([src]),
            )
            venv_symlinks.append(entry)
            continue

        if dir_name in dir_symlinks:
            # we already have this dir, this allows us to short-circuit since most of the
            # ctx.files.data might share the same directories as ctx.files.srcs
            continue

        if dir_name:
            # This can be either:
            # * a directory with libs (e.g. numpy.libs, created by auditwheel)
            # * a directory with `__init__.py` file that potentially also needs to be
            #   symlinked.
            # * `.dist-info` directory
            #
            # This could be also regular files, that just need to be symlinked, so we will
            # add the directory here.
            dir_symlinks[dir_name] = runfiles_dir_name
        elif src.extension in PYTHON_FILE_EXTENSIONS:
            # This would be files that do not have directories and we just need to add
            # direct symlinks to them as is, we only allow Python files in here
            entry = VenvSymlinkEntry(
                kind = VenvSymlinkKind.LIB,
                link_to_path = paths.join(runfiles_dir_name, site_packages_root, filename),
                link_to_file = src,
                package = package,
                version = version_str,
                venv_path = path,
                files = depset([src]),
            )
            venv_symlinks.append(entry)

    # Sort so that we encounter `foo` before `foo/bar`. This ensures we
    # see the top-most explicit package first.
    dirnames = sorted(dir_symlinks.keys())
    first_level_explicit_packages = []
    for d in dirnames:
        is_sub_package = False
        for existing in first_level_explicit_packages:
            # Suffix with / to prevent foo matching foobar
            if d.startswith(existing + "/"):
                is_sub_package = True
                break
        if not is_sub_package:
            first_level_explicit_packages.append(d)

    for dirname in first_level_explicit_packages:
        prefix = dir_symlinks[dirname]
        link_to_path = paths.join(prefix, site_packages_root, dirname)
        entry = VenvSymlinkEntry(
            kind = VenvSymlinkKind.LIB,
            link_to_path = link_to_path,
            package = package,
            version = version_str,
            venv_path = dirname,
            files = depset([
                f
                for f in all_files
                if runfiles_root_path(ctx, f.short_path).startswith(link_to_path + "/")
            ]),
        )
        venv_symlinks.append(entry)

    return venv_symlinks

def _is_linker_loaded_library(filename):
    """Tells if a filename is one that `dlopen()` or the runtime linker handles.

    This should return true for regular C libraries, but false for Python
    C extension modules.

    Python extensions: .so (linux, mac), .pyd (windows)

    C libraries: lib*.so (linux), lib*.so.* (linux), lib*.dylib (mac), .dll (windows)
    """
    if filename.endswith(".dll"):
        return True
    if filename.startswith("lib") and (
        filename.endswith((".so", ".dylib")) or ".so." in filename
    ):
        return True
    return False

def _repo_relative_short_path(short_path):
    # Convert `../+pypi+foo/some/file.py` to `some/file.py`
    if short_path.startswith("../"):
        return short_path[3:].partition("/")[2]
    else:
        return short_path
