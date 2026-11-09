"""The coverage tool for the WORKSPACE toolchains.

The bzlmod toolchains use the `@rules_python_coverage` pip hub, which is
created from the `uv.lock` file. The WORKSPACE macros cannot read the
`uv.lock` file, so the selected wheels are stored in the generated
`workspace_deps.bzl` file and this creates an equivalent hub repository from
it.

The WORKSPACE builds do not set the Python version flag by default, so there
is a target for each Python version in the hub, which only selects the wheel
based on the target platform.
"""

load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")
load("@bazel_tools//tools/build_defs/repo:utils.bzl", "maybe")
load("//python/private:text_util.bzl", "render")
load("//python/private/pypi:default_platforms.bzl", "default_platforms")
load(":workspace_deps.bzl", "COVERAGE_TOOLS", "COVERAGE_WHEELS")

_HUB_NAME = "rules_python_coverage"

def _wheel_repo_name(name):
    return "{}_{}".format(_HUB_NAME, name)

def _coverage_hub_repo_impl(rctx):
    platforms = json.decode(rctx.attr.platforms)
    tools = json.decode(rctx.attr.tools)

    used_platforms = sorted({
        p: None
        for by_platform in tools.values()
        for p in by_platform
    })

    rctx.file("BUILD.bazel", "\n".join([
        """load("@bazel_skylib//lib:selects.bzl", "selects")""",
        "",
        """package(default_visibility = ["//visibility:public"])""",
        "",
    ] + [
        render.call(
            "selects.config_setting_group",
            name = repr("is_" + p),
            match_all = render.list(platforms[p]),
        ) + "\n"
        for p in used_platforms
    ]))

    rctx.file("coverage/BUILD.bazel", "\n".join([
        """package(default_visibility = ["//visibility:public"])""",
        "",
    ] + [
        render.alias(
            name = python_version,
            actual = render.select(
                {
                    "//:is_" + p: "@{}//:pkg".format(_wheel_repo_name(name))
                    for p, name in sorted(by_platform.items())
                },
                no_match_error = repr((
                    "There is no coverage wheel for Python {} on the target " +
                    "platform. See the `python/private/coverage/workspace_deps.bzl` " +
                    "file in rules_python for the supported platforms."
                ).format(python_version)),
            ),
        ) + "\n"
        for python_version, by_platform in sorted(tools.items())
    ]))

coverage_hub_repo = repository_rule(
    implementation = _coverage_hub_repo_impl,
    attrs = {
        "platforms": attr.string(
            mandatory = True,
            doc = "JSON encoded dict of platform names to config setting labels.",
        ),
        "tools": attr.string(
            mandatory = True,
            doc = "JSON encoded dict of Python versions to platform names to wheel names.",
        ),
    },
    doc = "The hub repository for the coverage tool of the WORKSPACE toolchains.",
)

# The BUILD file for the extracted wheel. The `whl_library` is not used,
# because this is loaded before `py_repositories` defines the repositories that
# it needs.
_WHL_BUILD_FILE = """\
load("{py_library}", "py_library")

package(default_visibility = ["//visibility:public"])

py_library(
    name = "pkg",
    srcs = glob(["coverage/**/*.py"]),
    data = glob(
        ["coverage/**"],
        exclude = ["coverage/**/*.py"],
    ),
    imports = ["."],
)
"""

def coverage_tool(python_version):
    """Create the coverage repositories and return the coverage tool label.

    Args:
        python_version: {type}`str` the full Python version of the toolchain.

    Returns:
        {type}`str | None` the label of the coverage tool or `None` if there
        are no coverage wheels for the Python version.
    """
    major_minor = ".".join(python_version.split(".")[:2])
    if major_minor not in COVERAGE_TOOLS:
        return None

    build_file_content = _WHL_BUILD_FILE.format(
        py_library = str(Label("//python:py_library.bzl")),
    )
    for name, whl in COVERAGE_WHEELS.items():
        maybe(
            http_archive,
            name = _wheel_repo_name(name),
            build_file_content = build_file_content,
            integrity = whl["integrity"],
            type = "zip",
            urls = [whl["url"]],
        )

    maybe(
        coverage_hub_repo,
        name = _HUB_NAME,
        platforms = json.encode({
            name: [str(Label(setting)) for setting in values["config_settings"]]
            for name, values in default_platforms().items()
        }),
        tools = json.encode(COVERAGE_TOOLS),
    )

    return "@{}//coverage:{}".format(_HUB_NAME, major_minor)
