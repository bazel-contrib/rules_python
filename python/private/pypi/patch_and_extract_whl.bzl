""

load("//python/private:normalize_name.bzl", "normalize_name")
load("//python/private:repo_utils.bzl", "repo_utils")
load(":generate_whl_library_build_bazel.bzl", "generate_whl_library_build_bazel")
load(":labels.bzl", "DEFAULT_DATA_EXCLUDE")
load(":patch_whl.bzl", "get_whl_patches", "patch_whl")
load(":pep508_requirement.bzl", "requirement")
load(":pypi_repo_utils.bzl", "pypi_repo_utils")
load(":whl_extract.bzl", "whl_extract")
load(":whl_metadata.bzl", "parse_entry_points", "parse_whl_metadata", "whl_metadata")

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
    Return the fields of the PyPI PURL from the metadata.

    The PURL is built in the generated BUILD file, so that `@package_metadata`
    is not loaded by the repository rules.

    https://github.com/package-url/purl-spec/blob/main/types-doc/pypi-definition.md
    """

    # https://github.com/package-url/purl-spec/blob/main/types-doc/pypi-definition.md#name-definition
    purl = {
        "distribution": normalize_name(metadata.name).replace("_", "-"),
        "version": metadata.version,
    }
    if index:
        purl["repository_url"] = index
    if filename:
        purl["file_name"] = filename

    return purl

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

def _resolve_inspect_python(rctx, logger):
    if not (rctx.attr.python_interpreter or rctx.attr.python_interpreter_target):
        logger.fail(
            "experimental_action_install requires 'python_interpreter' or " +
            "'python_interpreter_target' to be set on '{}'".format(rctx.attr.name),
        )
        return None
    return pypi_repo_utils.resolve_python_interpreter(
        rctx,
        python_interpreter = rctx.attr.python_interpreter,
        python_interpreter_target = rctx.attr.python_interpreter_target,
    )

def _maybe_patch_whl(rctx, whl_path, whl_file):
    if not rctx.attr.whl_patches:
        return whl_path, whl_file, False
    patches = get_whl_patches(rctx.attr.whl_patches, whl_path.basename)
    if not patches:
        return whl_path, whl_file, False

    # patch_whl deletes its input before repacking. Never delete an
    # archive owned by another repository.
    if whl_path.dirname != rctx.path("."):
        rctx.symlink(whl_path, whl_path.basename)
        whl_path = rctx.path(whl_path.basename)
    whl_path = patch_whl(
        rctx,
        whl_path = whl_path,
        patches = patches,
    )
    return whl_path, None, True

def _inspect_whl_for_action_install(
        rctx,
        *,
        whl_path,
        patched,
        sdist_filename,
        annotation,
        logger):
    if patched:
        for entry in rctx.path(".").readdir():
            if entry.basename != whl_path.basename:
                rctx.delete(entry)

    data_exclude = (
        DEFAULT_DATA_EXCLUDE +
        (["**/*.dist-info/RECORD"] if sdist_filename else []) +
        rctx.attr.pip_data_exclude
    )
    inspect_args = [
        "-I",
        "-B",
        str(rctx.path(rctx.attr._inspect_whl)),
        "--wheel",
        str(whl_path),
    ]
    if annotation:
        for pattern in annotation.srcs_exclude_glob:
            inspect_args.extend(["--srcs-exclude-glob", pattern])
    for pattern in data_exclude + (annotation.data_exclude_glob if annotation else []):
        inspect_args.extend(["--data-exclude-glob", pattern])

    inspect_python = _resolve_inspect_python(rctx, logger)
    if not inspect_python:
        return None

    inspection = json.decode(pypi_repo_utils.execute_checked_stdout(
        rctx,
        python = inspect_python,
        srcs = [
            rctx.attr._inspect_whl,
            rctx.attr._wheel_layout,
        ],
        op = "InspectWhl({})".format(whl_path.basename),
        arguments = inspect_args,
        logger = logger,
    ))

    metadata = parse_whl_metadata(inspection["metadata_content"])
    if not (metadata.name and metadata.version):
        logger.fail("Failed to parse the wheel METADATA file in '{}'".format(whl_path.basename))
        return None

    extra_kwargs = {
        "action_install": True,
        "extracted_files": inspection["extracted_files"],
        "shebang_scripts": inspection["shebang_scripts"],
    }
    if inspection["has_entry_points_txt"]:
        rctx.file("entry_points.txt", inspection["entry_points_content"])
        extra_kwargs["has_entry_points_txt"] = True

    return struct(
        metadata = metadata,
        entry_points = parse_entry_points(inspection["entry_points_content"]),
        namespace_package_files = inspection["namespace_package_files"],
        data_exclude = data_exclude,
        extra_kwargs = extra_kwargs,
    )

def patch_and_extract_whl(rctx, *, whl_path, logger, sdist_filename = None, whl_file = None):
    """Extract the wheel, apply patches and generate BUILD.bazel files.

    Reused in pip and http wheel download code.

    Args:
        rctx: the repository ctx.
        whl_path: the whl path to extract.
        logger: The logger to use
        sdist_filename: The filename to ignore in the BUILD.bazel files as sources.
        whl_file: The label of an externally stored wheel, if any.

    Returns:
        The repository metadata if the extraction is reproducible
    """
    whl_path, whl_file, patched = _maybe_patch_whl(rctx, whl_path, whl_file)
    annotation = None if not rctx.attr.annotation else struct(**json.decode(rctx.read(rctx.attr.annotation)))

    if rctx.attr.experimental_action_install:
        inspected = _inspect_whl_for_action_install(
            rctx,
            whl_path = whl_path,
            patched = patched,
            sdist_filename = sdist_filename,
            annotation = annotation,
            logger = logger,
        )
        if inspected == None:
            return None
        metadata = inspected.metadata
        entry_points = inspected.entry_points
        namespace_package_files = inspected.namespace_package_files
        data_exclude = inspected.data_exclude
        extra_kwargs = inspected.extra_kwargs
    else:
        whl_extract(rctx, whl_path = whl_path, logger = logger)
        install_dir_path = rctx.path("site-packages")
        metadata = whl_metadata(
            install_dir = install_dir_path,
            read_fn = rctx.read,
            logger = logger,
        )
        namespace_package_files = pypi_repo_utils.find_namespace_package_files(rctx, install_dir_path)
        entry_points = _get_entry_points(rctx, install_dir_path, metadata)
        _move_scripts_needing_shebang_rewrite(rctx, entry_points)
        data_exclude = rctx.attr.pip_data_exclude
        extra_kwargs = {}

    if whl_file:
        extra_kwargs["whl_file"] = str(whl_file)

    rctx.file("metadata.json", json.encode_indent({
        "name": metadata.name,
        "provides_extra": metadata.provides_extra,
        "requires_dist": metadata.requires_dist,
        "version": metadata.version,
    }))

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
        annotation = annotation,
        data_exclude = data_exclude,
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
        logger = logger,
        **extra_kwargs
    )

    # The generated wheel target can obtain the original archive independently.
    # Do not retain the temporary download or delete a caller-owned wheel.
    if whl_file and whl_path.dirname == rctx.path("."):
        rctx.delete(whl_path)

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
