"""A simple whl extractor."""

load("@rules_python_internal//:rules_python_config.bzl", rp_config = "config")
load("//python/private:repo_utils.bzl", "repo_utils")
load(":whl_metadata.bzl", "find_whl_metadata")

# Mapping of wheel .data categories to their extraction destination (relative to
# repository root).
_DATA_CATEGORIES = {
    # category: repo_dest_dir
    "data": "data",
    "headers": "include",
    # In theory there may be directory collisions in platlib/purelib, so it is
    # best to merge the paths here. What is more, this code has to be reasonably
    # efficient because some packages like to explicitly indicate if something
    # is in `platlib` or `purelib` (e.g. libclang wheel).
    "platlib": "site-packages",
    "purelib": "site-packages",
    "scripts": "bin",
}

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
    data_dir = dist_info_dir.dirname.get_child(
        dist_info_dir.basename[:-len(".dist-info")] + ".data",
    )
    if data_dir.exists:
        for prefix, dest_prefix in _DATA_CATEGORIES.items():
            src = data_dir.get_child(prefix)
            if not src.exists:
                # The prefix does not exist in the wheel, we can continue
                continue

            dest_dir = rctx.path(dest_prefix)
            repo_utils.mkdir(rctx, dest_dir)
            for (src, dest) in merge_trees(src, dest_dir):
                logger.debug(lambda: "Renaming: {} -> {}".format(src, dest))
                repo_utils.rename(rctx, src, dest)

        # Move RECORD to rewrite-record so gen_wheel_record can generate
        # the platform-specific RECORD file at build time.
        record_file = dist_info_dir.get_child("RECORD")
        if record_file.exists:
            rewrite_record_dir = rctx.path(
                "rewrite-record/" + dist_info_dir.basename,
            )
            repo_utils.mkdir(rctx, rewrite_record_dir)
            repo_utils.rename(
                rctx,
                record_file,
                rewrite_record_dir.get_child("RECORD"),
            )

        # Ensure that there is no data dir left
        rctx.delete(data_dir)

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
            elif s.is_dir and d.is_dir:
                tmp.extend([(c, d.get_child(c.basename)) for c in s.readdir()])
            else:
                collisions.append((s, d))
        remaining = tmp

    if collisions:
        fail(
            "Collisions found while extracting:\n{}".format(
                "\n".join(["{} -> {}".format(s, d) for s, d in collisions]),
            ),
        )

    return ret
