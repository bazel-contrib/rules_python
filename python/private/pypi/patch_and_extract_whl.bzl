""

load("//python/private:normalize_name.bzl", "normalize_name")
load("//python/private:repo_utils.bzl", "repo_utils")
load(":generate_whl_library_build_bazel.bzl", "generate_whl_library_build_bazel")
load(":patch_whl.bzl", "patch_whl")
load(":pep508_requirement.bzl", "requirement")
load(":pypi_repo_utils.bzl", "pypi_repo_utils")
load(":whl_extract.bzl", "whl_extract")
load(":whl_metadata.bzl", "parse_entry_points", "whl_metadata")

def _get_entry_points(rctx, install_dir_path, metadata):
    dist_info_dir = "{}-{}.dist-info".format(
        metadata.name.replace("-", "_"),
        metadata.version.replace("-", "_"),
    )
    entry_points_txt = install_dir_path.get_child(dist_info_dir).get_child("entry_points.txt")
    if entry_points_txt.exists:
        return parse_entry_points(rctx.read(entry_points_txt))
    return {}

def _move_scripts_needing_shebang_rewrite(rctx, entry_points):
    bin_dir = rctx.path("bin")
    if not bin_dir.exists:
        return

    ep_names = {name.lower(): True for name in entry_points}
    for script in bin_dir.readdir():
        if script.is_dir:
            continue
        if script.basename.lower() in ep_names:
            rctx.delete(script)
            continue
        if script.basename.endswith(".exe") or script.basename.endswith(".dll"):
            continue
        content = rctx.read(script)
        if content.startswith("#!python"):
            rewrite_bin_dir = rctx.path("rewrite-bin")
            repo_utils.mkdir(rctx, rewrite_bin_dir)
            repo_utils.rename(rctx, script, rctx.path("rewrite-bin/" + script.basename))

def _to_purl(*, index, metadata, filename):
    """
    Produce a PyPI PURL from the metadata.

    https://github.com/package-url/purl-spec/blob/main/types-doc/pypi-definition.md
    """

    # https://github.com/package-url/purl-spec/blob/main/types-doc/pypi-definition.md#name-definition
    name = normalize_name(metadata.name).replace("_", "-")

    qualifiers = {}
    if index:
        qualifiers["repository_url"] = index
    if filename:
        qualifiers["file_name"] = filename

    return "pkg:pypi/{}@{}?{}".format(name, metadata.version, "&".join(["{}={}".format(key, val) for key, val in qualifiers.items()]))

def _remove_files(rctx, *basenames):
    paths = list(rctx.path(".").readdir())
    for _ in range(10000000):
        if not paths:
            break
        path = paths.pop()

        if path.basename in basenames:
            rctx.delete(path)
        elif path.is_dir:
            paths.extend(path.readdir())

def patch_and_extract_whl(rctx, *, whl_path, logger, sdist_filename = None):
    """Extract the wheel, apply patches and generate BUILD.bazel files.

    Reused in pip and http wheel download code.

    Args:
        rctx: the repository ctx.
        whl_path: the whl path to extract.
        logger: The logger to use
        sdist_filename: The filename to ignore in the BUILD.bazel files as sources.

    Returns:
        The repository metadata if the extraction is reproducible
    """
    if rctx.attr.whl_patches:
        patches = {}
        for patch_file, json_args in rctx.attr.whl_patches.items():
            patch_dst = struct(**json.decode(json_args))
            if whl_path.basename in patch_dst.whls:
                patches[patch_file] = patch_dst.patch_strip

        if patches:
            whl_path = patch_whl(
                rctx,
                whl_path = whl_path,
                patches = patches,
            )

    whl_extract(rctx, whl_path = whl_path, logger = logger)

    install_dir_path = whl_path.dirname.get_child("site-packages")
    metadata = whl_metadata(
        install_dir = install_dir_path,
        read_fn = rctx.read,
        logger = logger,
    )
    rctx.file("metadata.json", json.encode_indent({
        "name": metadata.name,
        "provides_extra": metadata.provides_extra,
        "requires_dist": metadata.requires_dist,
        "version": metadata.version,
    }))
    namespace_package_files = pypi_repo_utils.find_namespace_package_files(rctx, install_dir_path)

    entry_points = _get_entry_points(rctx, install_dir_path, metadata)
    _move_scripts_needing_shebang_rewrite(rctx, entry_points)

    build_file_contents = generate_whl_library_build_bazel(
        name = whl_path.basename,
        dep_template = rctx.attr.dep_template,
        sdist_filename = sdist_filename,
        config_load = rctx.attr.config_load,
        metadata_name = metadata.name,
        metadata_version = metadata.version,
        requires_dist = metadata.requires_dist,
        # TODO @aignas 2025-05-17: maybe have a build flag for this instead
        enable_implicit_namespace_pkgs = rctx.attr.enable_implicit_namespace_pkgs,
        # TODO @aignas 2025-04-14: load through the hub:
        annotation = None if not rctx.attr.annotation else struct(**json.decode(rctx.read(rctx.attr.annotation))),
        data_exclude = rctx.attr.pip_data_exclude,
        group_deps = rctx.attr.group_deps,
        group_name = rctx.attr.group_name,
        namespace_package_files = namespace_package_files,
        extras = requirement(rctx.attr.requirement).extras,
        entry_points = entry_points,
        purl = _to_purl(
            index = rctx.attr.index_url,
            metadata = metadata,
            filename = sdist_filename or whl_path.basename,
        ),
    )

    # Delete these in case the wheel had them. They generally don't cause
    # a problem, but let's avoid the chance of that happening.
    rctx.file("WORKSPACE")
    rctx.file("WORKSPACE.bazel")
    rctx.file("MODULE.bazel")
    rctx.file("REPO.bazel", """\
repo(
    default_package_metadata = [
        "//:package_metadata",
    ],
)
""")

    # BUILD files interfere with globbing and Bazel package boundaries.
    _remove_files(rctx, "BUILD", "BUILD.bazel")
    rctx.file("BUILD.bazel", build_file_contents)

    if hasattr(rctx, "repo_metadata"):
        return rctx.repo_metadata(reproducible = True)

    return None
