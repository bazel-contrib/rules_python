"""A simple whl extractor."""

load("@rules_python_internal//:rules_python_config.bzl", rp_config = "config")
load("//python/private:repo_utils.bzl", "repo_utils")
load(":whl_metadata.bzl", "find_whl_metadata")

def whl_extract(rctx, *, whl_path, logger):
    """Extract whls in Starlark.

    Args:
        rctx: the repository ctx.
        whl_path: the whl path to extract.
        logger: The logger to use
    """
    install_dir_path = rctx.path("site-packages")
    repo_utils.extract(
        rctx,
        archive = whl_path,
        output = install_dir_path,
        supports_whl_extraction = rp_config.supports_whl_extraction,
        extract_needs_chmod = rp_config.extract_needs_chmod,
    )

    metadata_file = find_whl_metadata(
        install_dir = install_dir_path,
        logger = logger,
    )

    # Get the <prefix>.dist_info dir name
    dist_info_dir = metadata_file.dirname
    rctx.file(
        dist_info_dir.get_child("INSTALLER"),
        "https://github.com/bazel-contrib/rules_python#pipstar",
    )

    # Get the <prefix>.dist_info dir name
    data_dir = dist_info_dir.dirname.get_child(dist_info_dir.basename[:-len(".dist-info")] + ".data")
    if data_dir.exists:
        for prefix, dest_prefix in {
            # https://docs.python.org/3/library/sysconfig.html#posix-prefix
            # We are taking this from the legacy whl installer config
            "data": "data",
            "headers": "include",
            # In theory there may be directory collisions here, so it would be best to
            # merge the paths here. We are doing for quite a few levels deep. What is
            # more, this code has to be reasonably efficient because some packages like
            # to not put everything to the top level, but to indicate explicitly if
            # something is in `platlib` or `purelib` (e.g. libclang wheel).
            "platlib": "site-packages",
            "purelib": "site-packages",
            "scripts": "bin",
        }.items():
            src = data_dir.get_child(prefix)
            if not src.exists:
                # The prefix does not exist in the wheel, we can continue
                continue

            dest_dir = rctx.path(dest_prefix)
            repo_utils.mkdir(rctx, dest_dir)
            for (src, dest) in merge_trees(src, dest_dir):
                logger.debug(lambda: "Renaming: {} -> {}".format(src, dest))
                repo_utils.rename(rctx, src, dest)

        _rewrite_record(rctx, dist_info_dir, data_dir.basename)

        # Ensure that there is no data dir left
        rctx.delete(data_dir)

_DATA_PREFIX_REWRITES = {
    "data/": "../../../",
    "headers/": "../../../include/",
    "platlib/": "",
    "purelib/": "",
    "scripts/": "../../../bin/",
}

# Visible for testing
def rewrite_record_content(content, data_dir_basename):
    """Rewrite RECORD file content to reflect extracted paths of .data contents.

    In a wheel archive, files destined for different installation schemes are
    stored under the `{distribution}-{version}.data/` directory (e.g. `purelib`,
    `platlib`, `scripts`, `headers`, `data`), and their archive member paths are
    recorded in `.dist-info/RECORD` with the `.data/` prefix.

    Per PEP 427 (https://peps.python.org/pep-0427/#the-data-directory) and
    PEP 376 (https://peps.python.org/pep-0376/#record), when a wheel is
    installed, files in `.data/` are unpacked into their target installation
    scheme locations (`purelib` and `platlib` into `site-packages`, `scripts`
    into `bin`, `headers` into `include`, and `data` into `data`/sys.prefix), and
    the `.data` directory is removed. The `RECORD` file is updated to list the
    installed paths relative to the directory containing `.dist-info` (i.e.
    `site-packages`).

    Tools such as `importlib.metadata.files()` resolve paths in `RECORD`
    relative to `site-packages`. Without rewriting `RECORD`, these tools attempt
    to locate files under the deleted `.data/` path and fail.

    Args:
        content: {type}`str` The original RECORD file content.
        data_dir_basename: {type}`str` The basename of the .data directory
            (e.g., "foo-1.0.data").

    Returns:
        {type}`str` The rewritten RECORD file content.
    """
    data_prefix = data_dir_basename + "/"
    quoted_data_prefix = '"' + data_prefix

    new_lines = []
    for line in content.splitlines():
        if not line:
            continue
        if line.startswith(data_prefix):
            rest = line[len(data_prefix):]
            for category, replacement in _DATA_PREFIX_REWRITES.items():
                if rest.startswith(category):
                    line = replacement + rest[len(category):]
                    break
        elif line.startswith(quoted_data_prefix):
            rest = line[len(quoted_data_prefix):]
            for category, replacement in _DATA_PREFIX_REWRITES.items():
                if rest.startswith(category):
                    line = '"' + replacement + rest[len(category):]
                    break
        new_lines.append(line)

    return "\n".join(new_lines) + "\n"

def _rewrite_record(rctx, dist_info_dir, data_dir_basename):
    record_file = dist_info_dir.get_child("RECORD")
    if not record_file.exists:
        return

    content = rctx.read(record_file)
    new_content = rewrite_record_content(content, data_dir_basename)
    rctx.file(record_file, new_content)

def merge_trees(src, dest):
    """Merge src into the destination path.

    This will attempt to merge-move src files to the destination directory if there are
    existing files. Fails at directory depth is 10000 or if there are collisions.

    Args:
        src: {type}`path` a src path to rename.
        dest: {type}`path` a dest path to rename to.

    Returns:
        A list of tuples for src and destination paths.
    """
    ret = []
    remaining = [(src, dest)]
    collisions = []
    for _ in range(10000):
        if collisions or not remaining:
            break

        tmp = []
        for (s, d) in remaining:
            if not d.exists:
                ret.append((s, d))
                continue

            if not s.is_dir or not d.is_dir:
                collisions.append(s)
                continue

            for file_or_dir in s.readdir():
                tmp.append((file_or_dir, d.get_child(file_or_dir.basename)))

        remaining = tmp

    if remaining:
        fail("Exceeded maximum directory depth of 10000 during tree merge.")

    if collisions:
        fail("Detected collisions between {} and {}: {}".format(src, dest, collisions))

    return ret
