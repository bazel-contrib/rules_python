"""Macro to generate all of the targets present in a {obj}`whl_library`."""

load("@bazel_skylib//lib:types.bzl", "types")
load("@bazel_skylib//rules:copy_file.bzl", "copy_file")
load("//python:py_library.bzl", "py_library")
load(":gen_wheel_record.bzl", "gen_wheel_record")
load(":generate_whl_library_build_bazel.bzl", "split_sdist_config_settings")
load(
    ":labels.bzl",
    "DATA_LABEL",
    "DEFAULT_DATA_EXCLUDE",
    "DIST_INFO_LABEL",
    "EXTRACTED_WHEEL_FILES",
    "PY_SRCS_LABEL",
    "WHEEL_DIR_PUBLIC_LABEL",
    "WHEEL_FILE",
)
load(":namespace_pkgs.bzl", _create_inits = "create_inits")
load(":py_sdist_wheel.bzl", "py_sdist_wheel")
load(":py_wheel_extract_files.bzl", "py_wheel_extract_files", "wheel_glob")
load(":py_wheel_library.bzl", "py_wheel_library")
load(":venv_entry_point.bzl", "venv_entry_point")
load(":venv_rewrite_shebang.bzl", "venv_rewrite_shebang")

# Files that are special to the Bazel processing of things.
_BAZEL_REPO_FILE_GLOBS = [
    "BUILD",
    "BUILD.bazel",
    "REPO.bazel",
    "WORKSPACE",
    "WORKSPACE.bzlmod",
    "WORKSPACE.bazel",
]

_IS_VENV_SITE_PACKAGES_YES = Label("//python/config_settings:_is_venvs_site_packages_yes")
_VENV_SITE_PACKAGES_FLAG = Label("//python/config_settings:venvs_site_packages")

def _add_copied_files_and_wheel_file(
        *,
        rules,
        native,
        copy_files,
        copy_executables,
        whl_file,
        name,
        visibility,
        data):
    for src, dest in copy_files.items():
        rules.copy_file(
            name = dest + ".copy",
            src = src,
            out = dest,
            visibility = visibility,
        )
        data.append(dest)
    for src, dest in copy_executables.items():
        rules.copy_file(
            name = dest + ".copy",
            src = src,
            out = dest,
            is_executable = True,
            visibility = visibility,
        )
        data.append(dest)

    if hasattr(native, "filegroup"):
        native.filegroup(
            name = WHEEL_FILE,
            srcs = [whl_file or name],
            visibility = visibility,
        )

def _is_wheel_internal_path(src, extracted_files, shebang_scripts):
    if src.startswith(("@", "//", ":")):
        return False
    if src.startswith(("site-packages/", "data/", "bin/", "include/")):
        return True
    if src in extracted_files:
        return True
    for s in shebang_scripts:
        if src == "bin/" + s or src == "bin/" + s + ".bat":
            return True
    return False

def _validate_action_install_args(
        name,
        *,
        sdist,
        filegroups,
        copy_files,
        copy_executables,
        extracted_files,
        shebang_scripts,
        _fail):
    if sdist != None:
        if filegroups != None:
            _fail(
                (
                    "In '{}', custom glob-based 'filegroups' ({}) are not supported for action-built sdists " +
                    "under experimental_action_install (use py_wheel_extract_files or wheel_glob on downloaded wheels)."
                ).format(name, ", ".join(sorted(filegroups.keys()))),
            )
            return False
        internal_copy_srcs = [
            src
            for src in list(copy_files.keys()) + list(copy_executables.keys())
            if _is_wheel_internal_path(src, extracted_files, shebang_scripts)
        ]
        if internal_copy_srcs:
            _fail(
                (
                    "In '{}', wheel-internal 'copy_files'/'copy_executables' ({}) are not supported for action-built sdists " +
                    "under experimental_action_install (use py_wheel_extract_files or wheel_glob on downloaded wheels)."
                ).format(name, ", ".join(sorted(internal_copy_srcs))),
            )
            return False
    if filegroups != None and not extracted_files and not shebang_scripts:
        _fail(
            (
                "In '{}', custom glob-based 'filegroups' ({}) are not supported with experimental_action_install " +
                "unless wheel file paths are known at loading time (or use py_wheel_extract_files on downloaded wheels)."
            ).format(name, ", ".join(sorted(filegroups.keys()))),
        )
        return False
    return True

def _add_action_install_copies(
        *,
        rules,
        native,
        copy_files,
        copy_executables,
        all_wheel_files,
        extracted_files,
        shebang_scripts,
        wheel_install_target,
        extract_state,
        visibility,
        data,
        _fail):
    can_extract_internal = hasattr(rules, "py_wheel_extract_files")
    for is_exec, copies in [(False, copy_files), (True, copy_executables)]:
        for src, dest in copies.items():
            if can_extract_internal and _is_wheel_internal_path(src, extracted_files, shebang_scripts):
                files_for_src = all_wheel_files if src in all_wheel_files else [src]
                copy_src = wheel_glob(
                    [src],
                    allow_empty = False,
                    files = files_for_src,
                    wheel_library = ":" + wheel_install_target,
                    is_executable = is_exec,
                    native = native,
                    extract_rule = rules.py_wheel_extract_files,
                    _state = extract_state,
                    _fail = _fail,
                )[0]
            else:
                copy_src = src
            copy_kwargs = dict(
                name = dest + ".copy",
                src = copy_src,
                out = dest,
                visibility = visibility,
            )
            if is_exec:
                copy_kwargs["is_executable"] = True
            rules.copy_file(**copy_kwargs)
            data.append(dest)

def _add_action_install_custom_filegroups(
        *,
        filegroups,
        rules,
        native,
        all_wheel_files,
        wheel_install_target,
        extract_state,
        bins_for_data_label,
        visibility,
        _fail):
    if filegroups == None:
        return
    for fg_name, glob_spec in sorted(filegroups.items()):
        if types.is_list(glob_spec):
            fg_include = glob_spec
            fg_exclude = []
        else:
            fg_include = glob_spec.get("include", [])
            fg_exclude = glob_spec.get("exclude", [])
        fg_srcs = (
            wheel_glob(
                fg_include,
                exclude = fg_exclude,
                allow_empty = True,
                files = all_wheel_files,
                wheel_library = ":" + wheel_install_target,
                native = native,
                extract_rule = rules.py_wheel_extract_files,
                _state = extract_state,
                _fail = _fail,
            ) if hasattr(rules, "py_wheel_extract_files") else []
        )
        if fg_name == DATA_LABEL:
            fg_srcs = fg_srcs + bins_for_data_label
        if hasattr(native, "filegroup"):
            native.filegroup(
                name = fg_name,
                srcs = fg_srcs,
                visibility = visibility,
            )

def whl_library_srcs(
        *,
        name,
        whl_file = None,
        sdist_filename = None,
        data_exclude = [],
        srcs_exclude = [],
        tags = [],
        filegroups = None,
        entry_points = {},
        data = [],
        copy_files = {},
        copy_executables = {},
        native = native,
        enable_implicit_namespace_pkgs = False,
        namespace_package_files = [],
        action_install = False,
        extracted_files = [],
        has_entry_points_txt = False,
        shebang_scripts = [],
        sdist = None,
        visibility = ["//visibility:public"],
        _fail = fail,
        rules = struct(
            copy_file = copy_file,
            py_library = py_library,
            py_sdist_wheel = py_sdist_wheel,
            py_wheel_extract_files = py_wheel_extract_files,
            py_wheel_library = py_wheel_library,
            venv_entry_point = venv_entry_point,
            venv_rewrite_shebang = venv_rewrite_shebang,
            gen_wheel_record = gen_wheel_record,
            create_inits = _create_inits,
        )):
    """Create all of the whl_library targets.

    Args:
        name: {type}`str` The file to match for including it into the `whl`
            filegroup. This may be also parsed to generate extra metadata.
        whl_file: {type}`str | None` The label of an externally stored wheel.
        sdist_filename: {type}`str | None` If the wheel was built from an sdist,
            the filename of the sdist.
        visibility: {type}`list[str]` The visibility of the source targets.
        tags: {type}`list[str]` The tags set on the `py_library`.
        entry_points: {type}`list[dict]` A list of parsed entry point definitions.
        filegroups: {type}`dict[str, list[str]] | None` A dictionary of the target
            names and the glob matches. If `None`, defaults will be used.
        copy_executables: {type}`dict[str, str]` The mapping between src and
            dest locations for the targets.
        copy_files: {type}`dict[str, str]` The mapping between src and
            dest locations for the targets.
        data_exclude: {type}`list[str]` The globs for data attribute exclusion
            in `py_library`.
        srcs_exclude: {type}`list[str]` The globs for srcs attribute exclusion
            in `py_library`.
        data: {type}`list[str]` A list of labels to include as part of the `data` attribute in `py_library`.
        enable_implicit_namespace_pkgs: {type}`boolean` generate __init__.py
            files for namespace pkgs.
        namespace_package_files: {type}`list[str]` A list of labels of files whose
            directories are namespace packages.
        action_install: {type}`bool` Whether to install the wheel in a build action.
        extracted_files: {type}`list[str]` Relative paths under the installed wheel directory.
        has_entry_points_txt: {type}`bool` Whether a fetch-time `entry_points.txt` file exists in the package.
        shebang_scripts: {type}`list[str]` Top-level script names in `.data/scripts/` with `#!python` shebangs.
        sdist: {type}`dict | None` Keyword arguments for `py_sdist_wheel` (plus `site_paths`) when building an sdist in an action.
        native: {type}`native` The native struct for overriding in tests.
        _fail: {type}`callable` The fail function for overriding in tests.
        rules: {type}`struct` A struct with references to rules for creating targets.
    """
    tags = sorted(tags)
    data = [] + data

    if action_install and not _validate_action_install_args(
        name,
        sdist = sdist,
        filegroups = filegroups,
        copy_files = copy_files,
        copy_executables = copy_executables,
        extracted_files = extracted_files,
        shebang_scripts = shebang_scripts,
        _fail = _fail,
    ):
        return

    bins_for_data_label = []
    for ep_dict in entry_points.values():
        kwargs = dict(ep_dict)
        ep_name = kwargs.pop("name")
        ep_target_name = "bin/{}".format(ep_name)
        rules.venv_entry_point(
            name = ep_target_name,
            **kwargs
        )
        bins_for_data_label.append(ep_target_name)
        data.append(ep_target_name)

    if action_install:
        all_wheel_files = list(extracted_files)
        for s in shebang_scripts:
            bin_s = "bin/" + s
            if bin_s not in all_wheel_files:
                all_wheel_files.append(bin_s)

        wheel_install_target = "_wheel_install" if sdist == None else PY_SRCS_LABEL
        extract_state = {}

        _add_action_install_copies(
            rules = rules,
            native = native,
            copy_files = copy_files,
            copy_executables = copy_executables,
            all_wheel_files = all_wheel_files,
            extracted_files = extracted_files,
            shebang_scripts = shebang_scripts,
            wheel_install_target = wheel_install_target,
            extract_state = extract_state,
            visibility = visibility,
            data = data,
            _fail = _fail,
        )

        if sdist != None:
            sdist_kwargs = dict(sdist)
            site_paths = sdist_kwargs.pop("site_paths", [])
            split_sdist_config_settings(sdist_kwargs)
            rules.py_sdist_wheel(
                name = name,
                sdist = sdist_filename,
                visibility = visibility,
                **sdist_kwargs
            )
        else:
            site_paths = []

        if hasattr(native, "filegroup"):
            # Note: For action-built sdists (`sdist != None`), `:whl_file` / `:whl`
            # points to `<dist>-<ver>.sdist_build.whl`: contents are the built wheel;
            # the filename is not a valid wheel filename — use `:whldir` for the real one.
            native.filegroup(
                name = WHEEL_FILE,
                srcs = [whl_file or name],
                visibility = visibility,
            )
            if sdist != None:
                native.filegroup(
                    name = WHEEL_DIR_PUBLIC_LABEL,
                    srcs = [name],
                    output_group = "whldir",
                    visibility = visibility,
                )

        _add_action_install_custom_filegroups(
            filegroups = filegroups,
            rules = rules,
            native = native,
            all_wheel_files = all_wheel_files,
            wheel_install_target = wheel_install_target,
            extract_state = extract_state,
            bins_for_data_label = bins_for_data_label,
            visibility = visibility,
            _fail = _fail,
        )

        if hasattr(native, "filegroup"):
            if filegroups == None or EXTRACTED_WHEEL_FILES not in filegroups:
                native.filegroup(
                    name = EXTRACTED_WHEEL_FILES,
                    srcs = [PY_SRCS_LABEL],
                    visibility = visibility,
                )
            if filegroups == None or DIST_INFO_LABEL not in filegroups:
                if sdist != None:
                    native.filegroup(
                        name = DIST_INFO_LABEL,
                        srcs = [":" + PY_SRCS_LABEL],
                        output_group = "dist_info",
                        visibility = visibility,
                    )
                else:
                    native.filegroup(
                        name = DIST_INFO_LABEL,
                        srcs = ["entry_points.txt"] if has_entry_points_txt else [],
                        visibility = visibility,
                    )
            if filegroups == None or DATA_LABEL not in filegroups:
                native.filegroup(
                    name = DATA_LABEL,
                    srcs = [PY_SRCS_LABEL] + bins_for_data_label,
                    visibility = visibility,
                )

        if hasattr(rules, "py_wheel_library"):
            common_wheel_kwargs = dict(
                extracted_files = extracted_files,
                shebang_scripts = shebang_scripts,
                namespace_package_files = namespace_package_files,
                srcs_exclude = srcs_exclude,
                data_exclude = data_exclude,
                enable_implicit_namespace_pkgs = enable_implicit_namespace_pkgs,
                tags = tags,
                experimental_venvs_site_packages = _VENV_SITE_PACKAGES_FLAG,
            )
            if site_paths:
                common_wheel_kwargs["site_paths"] = site_paths
            if sdist == None:
                # NOTE: `_wheel_install` is an internal implementation detail exposed with
                # `visibility` solely so `:wheel_files.bzl` (`wheel_glob`) can reference it
                # when loaded from external packages. Do not depend on `:_wheel_install`
                # directly; depend on `:srcs` (or `:pkg`) instead.
                rules.py_wheel_library(
                    name = wheel_install_target,
                    wheel = whl_file or name,
                    data = [],
                    visibility = visibility,
                    **common_wheel_kwargs
                )
                rules.py_wheel_library(
                    name = PY_SRCS_LABEL,
                    wheel = ":" + wheel_install_target,
                    data = data,
                    visibility = visibility,
                    **common_wheel_kwargs
                )
            else:
                rules.py_wheel_library(
                    name = PY_SRCS_LABEL,
                    wheel = name,
                    data = data,
                    visibility = visibility,
                    **common_wheel_kwargs
                )
        return

    existing_bin_names = {ep["name"].lower(): None for ep in entry_points.values()}
    for p in native.glob(["bin/*"], allow_empty = True):
        existing_bin_names[p[len("bin/"):].lower()] = None

    rewritten_script_names = []
    for src_path in native.glob(["rewrite-bin/*"], allow_empty = True):
        script_name = src_path[len("rewrite-bin/"):]
        if script_name.lower() in existing_bin_names:
            continue
        rewrite_target_name = "bin/{}".format(script_name)
        rules.venv_rewrite_shebang(
            name = rewrite_target_name,
            src = src_path,
            package = name,
        )
        bins_for_data_label.append(rewrite_target_name)
        data.append(rewrite_target_name)
        rewritten_script_names.append(script_name)

    record_srcs = native.glob(["rewrite-record/*/RECORD"], allow_empty = True)
    record_target_name = "record"
    if record_srcs:
        rules.gen_wheel_record(
            name = record_target_name,
            srcs = record_srcs,
            rewritten_scripts = rewritten_script_names,
            tags = ["manual"],
        )
        data.append(record_target_name)

    default_filegroups = {
        EXTRACTED_WHEEL_FILES: dict(
            include = ["**"],
            # The Bazel repo files are always excluded; only the sdist
            # filename is conditional on `sdist_filename`.
            exclude = _BAZEL_REPO_FILE_GLOBS + (
                [sdist_filename] if sdist_filename else []
            ),
        ),
        DIST_INFO_LABEL: dict(
            include = ["site-packages/*.dist-info/**"],
        ),
        DATA_LABEL: dict(
            include = ["data/**", "bin/**", "include/**"],
        ),
    }
    if filegroups == None:
        filegroups = default_filegroups
    elif filegroups:
        filegroups = default_filegroups | filegroups

    for filegroup_name, glob_kwargs in filegroups.items():
        if types.is_list(glob_kwargs):
            glob_kwargs = {"include": glob_kwargs}
        glob_kwargs = {"allow_empty": True} | glob_kwargs
        srcs = native.glob(**glob_kwargs)
        if filegroup_name == DATA_LABEL:
            srcs = srcs + bins_for_data_label
        if filegroup_name == DIST_INFO_LABEL and record_srcs:
            srcs = srcs + [record_target_name]
        native.filegroup(
            name = filegroup_name,
            srcs = srcs,
            visibility = visibility,
        )

    _add_copied_files_and_wheel_file(
        rules = rules,
        native = native,
        copy_files = copy_files,
        copy_executables = copy_executables,
        whl_file = whl_file,
        name = name,
        visibility = visibility,
        data = data,
    )

    if hasattr(rules, "py_library"):
        srcs = native.glob(
            ["site-packages/**/*.py"],
            exclude = srcs_exclude,
            # Empty sources are allowed to support wheels that don't have any
            # pure-Python code, e.g. pymssql, which is written in Cython.
            allow_empty = True,
        )

        # NOTE: pyi files should probably be excluded because they're carried
        # by the pyi_srcs attribute. However, historical behavior included
        # them in data and some tools currently rely on that.
        _data_exclude = ["**/*.py"] + DEFAULT_DATA_EXCLUDE
        if sdist_filename:
            _data_exclude.append("**/*.dist-info/RECORD")
        for item in data_exclude:
            if item not in _data_exclude:
                _data_exclude.append(item)

        data = data + native.glob(
            ["site-packages/**/*"],
            exclude = _data_exclude,
            allow_empty = True,
        )

        pyi_srcs = native.glob(
            ["site-packages/**/*.pyi", "site-packages/**/py.typed"],
            allow_empty = True,
        )

        if not enable_implicit_namespace_pkgs:
            generated_namespace_package_files = select({
                _IS_VENV_SITE_PACKAGES_YES: [],
                "//conditions:default": rules.create_inits(
                    srcs = srcs + data + pyi_srcs,
                    ignored_dirnames = [],  # If you need to ignore certain folders, you can patch rules_python here to do so.
                    root = "site-packages",
                ),
            })
            namespace_package_files += generated_namespace_package_files
            srcs = srcs + generated_namespace_package_files

        # This is done after create_inits() is called so that the data scheme
        # files don't have such files created in their directories.
        data = data + [DATA_LABEL]

        rules.py_library(
            name = PY_SRCS_LABEL,
            srcs = srcs,
            pyi_srcs = pyi_srcs,
            data = data,
            # This makes this directory a top-level in the python import
            # search path for anything that depends on this.
            imports = ["site-packages"],
            tags = tags,
            visibility = visibility,
            experimental_venvs_site_packages = _VENV_SITE_PACKAGES_FLAG,
            namespace_package_files = namespace_package_files,
        )
