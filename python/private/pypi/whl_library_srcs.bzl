"""Macro to generate all of the targets present in a {obj}`whl_library`."""

load("@bazel_skylib//rules:copy_file.bzl", "copy_file")
load("//python:py_library.bzl", "py_library")
load(":gen_wheel_record.bzl", "gen_wheel_record")
load(
    ":labels.bzl",
    "DATA_LABEL",
    "DIST_INFO_LABEL",
    "EXTRACTED_WHEEL_FILES",
    "PY_SRCS_LABEL",
    "WHEEL_FILE",
)
load(":namespace_pkgs.bzl", _create_inits = "create_inits")
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

def whl_library_srcs(
        *,
        name,
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
        visibility = ["//visibility:public"],
        rules = struct(
            copy_file = copy_file,
            py_library = py_library,
            venv_entry_point = venv_entry_point,
            venv_rewrite_shebang = venv_rewrite_shebang,
            gen_wheel_record = gen_wheel_record,
            create_inits = _create_inits,
        )):
    """Create all of the whl_library targets.

    Args:
        name: {type}`str` The file to match for including it into the `whl`
            filegroup. This may be also parsed to generate extra metadata.
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
        native: {type}`native` The native struct for overriding in tests.
        rules: {type}`struct` A struct with references to rules for creating targets.
    """
    tags = sorted(tags)
    data = [] + data

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

    if filegroups == None:
        filegroups = {
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

    for filegroup_name, glob_kwargs in filegroups.items():
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
            srcs = [name],
            visibility = visibility,
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
        _data_exclude = [
            "**/*.py",
            "**/*.pyc",
            "**/*.pyc.*",  # During pyc creation, temp files named *.pyc.NNNN are created
        ]
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
            ["site-packages/**/*.pyi"],
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
