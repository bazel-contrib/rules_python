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

load("//python/private:text_util.bzl", "render")
load(":labels.bzl", "DATA_LABEL", "DIST_INFO_LABEL", "EXTRACTED_WHEEL_FILES", "PACKAGE_METADATA_LABEL")

# These are functions on how to render particular args, should be reused across all rendering
# invocations to make things easier.
_RENDER_FNS = {
    "aliases": render.list,
    "copy_executables": render.dict,
    "copy_files": render.dict,
    "data": render.list,
    "data_exclude": render.list,
    "entry_points": render.dict_dict,
    "extras": render.list,
    "group_deps": render.list,
    "include": str,
    "requires_dist": render.list,
    "srcs_exclude": render.list,
    "tags": render.list,
}

def _render(**kwargs):
    return {
        arg: _RENDER_FNS.get(arg, repr)(value)
        for arg, value in kwargs.items()
    }

# NOTE @aignas 2024-10-25: We have to keep this so that files in
# this repository can be publicly visible without the need for
# export_files
_TEMPLATE = """\
{loads}

package(default_visibility = ["//visibility:public"])

{macros}
"""

def generate_whl_library_build_bazel(
        *,
        name,
        annotation = None,
        config_load,
        copy_executables = {},
        copy_files = {},
        data_exclude = [],
        dep_template,
        enable_implicit_namespace_pkgs = False,
        entry_points = {},
        extras = [],
        group_deps = [],
        group_name = None,
        metadata_name,
        metadata_version,
        namespace_package_files = {},
        purl = None,
        requires_dist = [],
        sdist_filename = None,
        srcs_exclude = [],
        visibility = ["//visibility:public"],
        **kwargs):
    """Generate a BUILD file for an unzipped Wheel

    Args:
        annotation: The annotation for the build file.
        config_load: {type}`str` The location from where to load the config.
        purl: The purl.
        requires_dist: {type}`list[str]` The list of dependencies from the METADATA file.
        **kwargs: Extra args serialized to be passed to the
            {obj}`whl_library_targets`.

    Returns:
        A complete BUILD file as a string
    """

    loads = [
        """load("@package_metadata//rules:package_metadata.bzl", "package_metadata")""",
        """load("@rules_python//python/private/pypi:whl_library_targets.bzl", "whl_library_srcs", "whl_library_from_requires_dist")""",
    ]

    srcs_kwargs = dict(
        name = name,
        data = [],
        sdist_filename = sdist_filename,
        data_exclude = list(data_exclude),
        srcs_exclude = list(srcs_exclude),
        tags = [
            "pypi_name={}".format(metadata_name),
            "pypi_version={}".format(metadata_version),
        ],
        entry_points = entry_points,
        enable_implicit_namespace_pkgs = enable_implicit_namespace_pkgs,
        copy_files = copy_files,
        copy_executables = copy_executables,
        namespace_package_files = namespace_package_files,
        visibility = visibility,
    )

    # NOTE, if users specify annotations, the wheel downloads are not reused this
    # is to ensure that we don't break users config and also to ensure that we
    # can have predictable results.
    additional_content = []
    if annotation:
        kwargs["data"] = annotation.data
        kwargs["copy_files"] = annotation.copy_files
        kwargs["copy_executables"] = annotation.copy_executables
        kwargs["data_exclude"] = kwargs.get("data_exclude", []) + annotation.data_exclude_glob
        kwargs["srcs_exclude"] = annotation.srcs_exclude_glob
        if annotation.additive_build_content:
            additional_content.append(annotation.additive_build_content)

    macro_parts = [
        render.call(
            "package_metadata",
            **_render(
                name = PACKAGE_METADATA_LABEL,
                purl = purl,
                visibility = ["//:__subpackages__"],
            )
        ),
        render.call(
            "whl_library_srcs",
            **_render(**srcs_kwargs)
        ),
    ]

    if dep_template:
        from_requires_kwargs = dict(
            name = metadata_name,
            version = metadata_version,
            requires_dist = requires_dist,
            extras = extras,
            group_deps = group_deps,
            dep_template = dep_template,
            group_name = group_name,
        )

        if config_load:
            loads.append("""load("{}", "{}")""".format(config_load, "packages"))
            from_requires_kwargs["include"] = "packages"

        macro_parts.append(render.call(
            "whl_library_from_requires_dist",
            **_render(**from_requires_kwargs)
        ))

    contents = "\n".join(
        [
            _TEMPLATE.format(
                loads = "\n".join(loads),
                macros = "\n\n".join(macro_parts),
            ),
        ] + additional_content,
    )

    # NOTE: Ensure that we terminate with a new line
    return contents.rstrip() + "\n"

def generate_whl_library_deps_build_bazel(
        *,
        name,
        version,
        config_load,
        dep_template,
        entry_points,
        extras,
        group_deps,
        group_name,
        requires_dist,
        whl_library,
        **kwargs):
    """Generate a BUILD file for an unzipped Wheel


    Returns:
        A complete BUILD file as a string
    """

    loads = [
        """load("@rules_python//python/private/pypi:whl_library_targets.bzl", "whl_library_from_requires_dist")""",
    ]

    from_requires_kwargs = dict(
        name = name,
        version = version,
        requires_dist = requires_dist,
        extras = extras,
        group_deps = group_deps,
        dep_template = dep_template,
        group_name = group_name,
        src_pkg = str(whl_library),
        aliases = [
            DATA_LABEL,
            DIST_INFO_LABEL,
            EXTRACTED_WHEEL_FILES,
        ] + [
            "bin/{}".format(entry_point)
            for entry_point in entry_points
        ],
    )

    if config_load:
        loads.append("""load("{}", "{}")""".format(config_load, "packages"))
        from_requires_kwargs["include"] = "packages"

    macro_parts = [render.call(
        "whl_library_from_requires_dist",
        **_render(**from_requires_kwargs)
    )]

    contents = _TEMPLATE.format(
        loads = "\n".join(loads),
        macros = "\n\n".join(macro_parts),
    )

    # NOTE: Ensure that we terminate with a new line
    return contents.rstrip() + "\n"
