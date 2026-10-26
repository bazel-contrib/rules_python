# Copyright 2023 The Bazel Authors. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

"""Generate the BUILD.bazel contents for a repo defined by a whl_library."""

load("@bazel_skylib//lib:types.bzl", "types")
load("//python/private:text_util.bzl", "render")

_RENDER = {
    "copy_executables": render.dict,
    "copy_files": render.dict,
    "data": render.list,
    "data_exclude": render.list,
    "entry_points": render.dict_dict,
    "extracted_files": render.list,
    "extras": render.list,
    "filegroups": render.dict,
    "group_deps": render.list,
    "include": str,
    "repo": lambda maybe_label: repr(str(maybe_label)),
    "requires_dist": render.list,
    "sdist": render.dict,
    "shebang_scripts": render.list,
    "srcs_exclude": render.list,
    "tags": render.list,
}

# NOTE @aignas 2024-10-25: We have to keep this so that files in
# this repository can be publicly visible without the need for
# export_files
_TEMPLATE = """\
{loads}

package(default_visibility = ["//visibility:public"])

{fn}(
{kwargs}
)
"""

_PACKAGE_METADATA = """\
whl_package_metadata(
{kwargs}
)
"""

def _check_additive_build_content_for_glob(content):
    """Return True if `content` contains a non-`wheel_glob` `glob(` call outside comments."""
    for raw_line in content.splitlines():
        line = raw_line.split("#", 1)[0]
        without_wheel_glob = line.replace("wheel_glob(", "").replace("wheel_glob (", "")
        if "glob(" in without_wheel_glob or "glob (" in without_wheel_glob:
            return True
    return False

_QUIET_SDIST_PIP_FLAGS_NO_VALUE = {
    "--disable-pip-version-check": True,
    "--isolated": True,
    "--no-cache-dir": True,
    "--no-color": True,
    "--no-deps": True,
    "--no-index": True,
    "--pre": True,
    "--prefer-binary": True,
    "--quiet": True,
    "--require-hashes": True,
    "--use-pep517": True,
    "--verbose": True,
    "-q": True,
    "-v": True,
}

_QUIET_SDIST_PIP_FLAGS_WITH_VALUE = {
    "--abi": True,
    "--cache-dir": True,
    "--cert": True,
    "--client-cert": True,
    "--exists-action": True,
    "--extra-index-url": True,
    "--find-links": True,
    "--implementation": True,
    "--index-url": True,
    "--keyring-provider": True,
    "--log": True,
    "--no-binary": True,
    "--only-binary": True,
    "--platform": True,
    "--progress-bar": True,
    "--proxy": True,
    "--python-version": True,
    "--retries": True,
    "--timeout": True,
    "--trusted-host": True,
    "-f": True,
    "-i": True,
}

def _add_config_setting(config_settings, key, value):
    if key in config_settings:
        existing = config_settings[key]
        if types.is_list(existing):
            existing.append(value)
        else:
            config_settings[key] = [existing, value]
    else:
        config_settings[key] = value

def split_sdist_config_settings(sdist_dict):
    """Split list-valued entries in `sdist_dict["config_settings"]` into `config_settings_list`.

    Args:
        sdist_dict: {type}`dict` Mutable sdist keyword arguments dict updated in place.
    """
    if "config_settings" not in sdist_dict:
        return
    scalar_cs = {}
    list_cs = dict(sdist_dict.get("config_settings_list", {}))
    for k, v in sdist_dict["config_settings"].items():
        if types.is_list(v):
            list_cs[k] = v
        else:
            scalar_cs[k] = v
    if scalar_cs:
        sdist_dict["config_settings"] = scalar_cs
    else:
        sdist_dict.pop("config_settings")
    if list_cs:
        sdist_dict["config_settings_list"] = list_cs

def parse_sdist_extra_pip_args(extra_pip_args, logger = None, name = ""):
    """Parse `extra_pip_args` for an action-mode sdist build.

    Extracts `-C` / `--config-settings` into a `config_settings` dict (accumulating
    repeated keys into lists), silently ignores standard index/network/fetch flags,
    and warns via `logger.warn` on any other unrecognized args.

    Args:
        extra_pip_args: {type}`list[str]` Extra pip arguments configured on the repo.
        logger: Optional repository logger used to emit warnings.
        name: {type}`str` Package or sdist filename for warning messages.

    Returns:
        {type}`dict[str, str | list[str]]` Parsed PEP 517 config settings.
    """
    config_settings = {}
    ignored = []
    mode = None

    for raw_arg in extra_pip_args or []:
        if mode == "config_setting":
            k, has_eq, v = raw_arg.partition("=")
            _add_config_setting(config_settings, k, v if has_eq else "")
            mode = None
            continue
        if mode == "skip_value":
            mode = None
            continue

        if raw_arg in ("-C", "--config-settings", "--config-setting"):
            mode = "config_setting"
            continue
        if raw_arg.startswith("--config-settings="):
            kv = raw_arg[len("--config-settings="):]
            k, has_eq, v = kv.partition("=")
            _add_config_setting(config_settings, k, v if has_eq else "")
            continue
        if raw_arg.startswith("--config-setting="):
            kv = raw_arg[len("--config-setting="):]
            k, has_eq, v = kv.partition("=")
            _add_config_setting(config_settings, k, v if has_eq else "")
            continue
        if raw_arg.startswith("-C") and len(raw_arg) > 2:
            kv = raw_arg[2:]
            k, has_eq, v = kv.partition("=")
            if has_eq:
                _add_config_setting(config_settings, k, v)
                continue

        if raw_arg in _QUIET_SDIST_PIP_FLAGS_NO_VALUE:
            continue
        if raw_arg in _QUIET_SDIST_PIP_FLAGS_WITH_VALUE:
            mode = "skip_value"
            continue
        flag_name, has_eq, _ = raw_arg.partition("=")
        if has_eq and flag_name in _QUIET_SDIST_PIP_FLAGS_WITH_VALUE:
            continue
        if (raw_arg.startswith("-i") or raw_arg.startswith("-f")) and len(raw_arg) > 2 and not raw_arg.startswith("--"):
            continue

        ignored.append(raw_arg)

    if ignored and logger:
        logger.warn(
            "In '{}', extra_pip_args {} are ignored in experimental_action_install sdist builds (use -C / --config-settings or sdist_config_settings instead).".format(
                name,
                ignored,
            ),
        )
    return config_settings

def generate_whl_library_build_bazel(
        *,
        metadata_version,
        annotation = None,
        config_load,
        purl = None,
        requires_dist = [],
        logger = None,
        **kwargs):
    """Generate a BUILD file for an unzipped Wheel

    Args:
        metadata_version: The version to use for tag generation.
        annotation: The annotation for the build file.
        config_load: {type}`str` The location from where to load the config.
        purl: {type}`dict[str, str] | None` The fields of the PyPI PURL passed
            to {obj}`whl_package_metadata`.
        requires_dist: {type}`list[str]` The list of dependencies from the METADATA file.
        logger: Optional repository logger used to emit warnings.
        **kwargs: Extra args serialized to be passed to the
            {obj}`whl_library_targets`.

    Returns:
        A complete BUILD file as a string
    """

    loads = []

    if kwargs.get("repo"):
        fn = "whl_library_deps_targets"
    else:
        fn = "whl_library_targets"

    tags = [
        "pypi_name={}".format(kwargs.get("metadata_name")),
        "pypi_version={}".format(metadata_version),
    ]
    kwargs["tags"] = tags

    sdist = kwargs.get("sdist")
    if sdist != None:
        sdist = dict(sdist)
        if annotation:
            if hasattr(annotation, "sdist_build_deps") and annotation.sdist_build_deps:
                sdist["build_deps"] = annotation.sdist_build_deps
            if hasattr(annotation, "sdist_config_settings") and annotation.sdist_config_settings:
                sdist["config_settings"] = dict(sdist.get("config_settings", {})) | dict(annotation.sdist_config_settings)
            if hasattr(annotation, "site_paths") and annotation.site_paths:
                sdist["site_paths"] = annotation.site_paths
        split_sdist_config_settings(sdist)
        kwargs["sdist"] = {k: sdist[k] for k in sorted(sdist)}

    if not requires_dist and not (sdist and sdist.get("build_requires")):
        # no deps, we can leave the extra loads out
        pass
    elif config_load:
        loads.append("""load("{}", "{}")""".format(config_load, "packages"))
        kwargs["include"] = "packages"
        if requires_dist:
            kwargs["requires_dist"] = requires_dist
    elif requires_dist:
        kwargs["requires_dist"] = requires_dist

    loads.extend([
        """load("@rules_python//python/private/pypi:{}.bzl", "{}")""".format(fn, fn),
    ])
    if purl:
        loads.append("""load("@rules_python//python/private/pypi:whl_package_metadata.bzl", "whl_package_metadata")""")

    additional_content = []
    if annotation:
        kwargs["data"] = annotation.data
        kwargs["copy_files"] = annotation.copy_files
        kwargs["copy_executables"] = annotation.copy_executables
        kwargs["data_exclude"] = kwargs.get("data_exclude", []) + annotation.data_exclude_glob
        kwargs["srcs_exclude"] = annotation.srcs_exclude_glob
        if hasattr(annotation, "filegroups") and annotation.filegroups and "filegroups" not in kwargs:
            kwargs["filegroups"] = annotation.filegroups
        if annotation.additive_build_content:
            should_warn_glob = (
                kwargs.get("action_install") and
                logger != None and
                _check_additive_build_content_for_glob(annotation.additive_build_content)
            )
            if should_warn_glob:
                logger.warn(
                    (
                        "In '{}', annotation 'additive_build_content' may glob wheel contents; " +
                        "globs match nothing under experimental_action_install — use wheel_glob(), " +
                        "py_wheel_headers, py_wheel_transform, post_install_patches, or " +
                        "py_wheel_extract_files instead."
                    ).format(kwargs.get("name", kwargs.get("metadata_name", ""))),
                )
            if (
                "wheel_glob(" in annotation.additive_build_content or
                "wheel_glob (" in annotation.additive_build_content
            ):
                loads.append(
                    """load("@rules_python//python/private/pypi:py_wheel_extract_files.bzl", "wheel_glob")""",
                )
            if (
                "wheel_extract_prefix(" in annotation.additive_build_content or
                "wheel_extract_prefix (" in annotation.additive_build_content
            ):
                loads.append(
                    """load("@rules_python//python/private/pypi:py_wheel_extract_files.bzl", "wheel_extract_prefix")""",
                )
            additional_content.append(annotation.additive_build_content)

    contents = "\n".join(
        [
            _TEMPLATE.format(
                loads = "\n".join(loads),
                fn = fn,
                kwargs = render.indent("\n".join([
                    "{} = {},".format(k, _RENDER.get(k, repr)(v))
                    for k, v in sorted(kwargs.items())
                ])),
            ),
        ] + ([_PACKAGE_METADATA.format(kwargs = render.indent("\n".join([
            "{} = {},".format(k, repr(v))
            for k, v in sorted(purl.items())
        ])))] if purl else []) + additional_content,
    )

    # NOTE: Ensure that we terminate with a new line
    return contents.rstrip() + "\n"

def generate_wheel_files_bzl(extracted_files):
    """Generate the contents of `wheel_files.bzl` for a wheel repository.

    Args:
        extracted_files: {type}`list[str]` Sorted list of wheel-relative file paths.

    Returns:
        {type}`str` Starlark source for `wheel_files.bzl`.
    """
    return """\
\"\"\"Generated wheel file list and wheel_glob wrapper.\"\"\"

load("@rules_python//python/private/pypi:py_wheel_extract_files.bzl", _wheel_glob = "wheel_glob")  # buildifier: disable=bzl-visibility

FILES = {files}

def wheel_glob(
        include,
        exclude = [],
        exclude_directories = 1,
        allow_empty = True,
        *,
        wheel_library = Label("//:_wheel_install"),
        is_executable = False):
    \"\"\"Glob over wheel files in this repository.\"\"\"
    return _wheel_glob(
        include = include,
        exclude = exclude,
        exclude_directories = exclude_directories,
        allow_empty = allow_empty,
        files = FILES,
        wheel_library = wheel_library,
        is_executable = is_executable,
    )
""".format(
        files = render.list(extracted_files),
    )

def generate_sdist_wheel_files_bzl():
    """Generate stub `wheel_files.bzl` for an action-built sdist repository.

    Returns:
        {type}`str` Starlark source for `wheel_files.bzl` that fails with guidance on `wheel_glob()`.
    """
    return """\
FILES = []

def wheel_glob(*args, **kwargs):
    fail(
        "wheel_glob() cannot be used with an action-built sdist because wheel contents " +
        "are not known at loading time under experimental_action_install. Use a " +
        "pre-built wheel or py_wheel_headers / py_wheel_transform instead.",
    )
"""
