"""A module extension for uv external dependencies.

This extension allows users to define external dependencies using uv.
"""

load("@bazel_skylib//lib:selects.bzl", "selects")
load("//python/private:repo_utils.bzl", "REPO_DEBUG_ENV_VAR", "repo_utils")
load("//python/private:text_util.bzl", "render")
load("//python/private/pypi:env_marker_setting.bzl", "env_marker_setting")
load("//python/private/pypi:pypi_repo_utils.bzl", "pypi_repo_utils")
load("//python/private/pypi:wheel_tags_setting.bzl", "wheel_tags_setting")

def _convert_uv_lock_to_json(mrctx, attr, logger):
    python_interpreter = pypi_repo_utils.resolve_python_interpreter(
        mrctx,
        python_interpreter_target = attr._python_interpreter_target,
    )
    toml2json = mrctx.path(attr._toml2json)
    src_path = mrctx.path(attr.srcs[0])

    stdout = pypi_repo_utils.execute_checked_stdout(
        mrctx,
        logger = logger,
        op = "toml2json",
        python = python_interpreter,
        arguments = [
            str(toml2json),
            str(src_path),
        ],
        srcs = [toml2json, src_path],
    )
    return stdout

def _wheel_repo_impl(rctx):
    rctx.download(rctx.attr.urls, output = "output.zip")
    rctx.file("BUILD.bazel", "exports_files(glob(['**']))")

wheel_repo = repository_rule(
    implementation = _wheel_repo_impl,
    attrs = {
        "urls": attr.string_list(),
    },
)

_PACKAGE_BUILD_TEMPLATE = """

load("@rules_python//python/extensions:uv_external_deps.bzl", "define_targets")

package(
    default_visibility = ["//visibility:public"]
)
exports_files(glob(["**"]))

define_targets(
    name = "{package}",
    selectors = {selectors}
)
"""

def _hub_package_build_file(rctx, package, selectors):
    rctx.file(
        "{}/BUILD.bazel".format(package),
        _PACKAGE_BUILD_TEMPLATE.format(
            package = package,
            selectors = render.list(selectors),
        ),
    )

def _hub_repo_impl(rctx):
    hub_selectors = json.decode(rctx.attr.selectors)

    for package, selectors in hub_selectors.items():
        _hub_package_build_file(rctx, package, selectors)

    rctx.file("BUILD.bazel", "")

hub_repo = repository_rule(
    implementation = _hub_repo_impl,
    attrs = {
        "selectors": attr.string(),
    },
)

def wheel_tags_from_wheel_url(url):
    _, _, basename = url.rpartition("/")
    basename = basename.removesuffix(".whl")
    distro, _, tail = basename.partition("-")
    version, _, tail = tail.partition("-")
    py_tag, _, tail = tail.partition("-")
    abi, _, tail = tail.partition("-")
    platform, _, tail = tail.partition("-")
    return {
        "python_tag": py_tag,
        "abi_tag": abi,
        "platform_tag": platform,
    }
    #charset_normalizer-3.4.4-cp310-cp310-macosx_10_9_universal2.whl",

def _uv_external_deps_extension_impl(mctx):
    logger = repo_utils.logger(mctx, "uvextdeps")

    # sources[distro][version][type][url] = any_of_conditions
    # url -> info
    sources = {}
    hub_name = None
    for mod in mctx.modules:
        for hub in mod.tags.hub:
            out = _convert_uv_lock_to_json(mctx, hub, logger)
            lock_info = json.decode(out)
            break

    # Basically what we're doing is:
    # URLs are given name R (repo name). Thus, we never duplicate a download.
    # Repo R is used if conditions C are met (wheel tags, marker, and
    # custom config settings for that lock file).
    url_to_repo = {}
    hub_selectors = {}

    packages = lock_info["package"]
    for distro in packages:
        # todo: handle source{virtual = "."}
        if "wheels" not in distro:
            continue
        for i, wheel in enumerate(distro["wheels"]):
            url = wheel["url"]
            if url not in url_to_repo:
                # todo: normalize dash to underscore etc
                name = "{distro}_{version}_{i}".format(
                    distro = distro["name"],
                    version = distro["version"],
                    i = i,
                )
                wheel_repo(
                    name = name,
                    urls = [url],
                )
            else:
                name = url_to_repo[url]

            hub_selectors.setdefault(distro["name"], [])
            wheel_tags = wheel_tags_from_wheel_url(url)
            resolution_markers = distro.get("resolution-markers")
            if resolution_markers:
                for marker in resolution_markers:
                    hub_selectors[distro["name"]].append(struct(
                        wheel_tags = wheel_tags,
                        config_settings = hub.config_settings,
                        marker = marker,
                        actual_repo = name,
                    ))
            else:
                hub_selectors[distro["name"]].append(struct(
                    wheel_tags = wheel_tags,
                    config_settings = hub.config_settings,
                    marker = None,
                    actual_repo = name,
                ))

    hub_repo(
        name = hub.name,
        selectors = json.encode(hub_selectors),
    )

uv_external_deps = module_extension(
    implementation = _uv_external_deps_extension_impl,
    tag_classes = {
        "hub": tag_class(attrs = {
            "name": attr.string(),
            "srcs": attr.label_list(),
            "config_settings": attr.label_list(),
            "_toml2json": attr.label(default = "//tools/toml2json:toml2json.py"),
            "_python_interpreter_target": attr.label(
                default = "@python_3_14_host//:python",
            ),
        }),
    },
)

def gen_package_config_settings(name, config_settings, marker, wheel_tags):
    match_all = list(config_settings)
    wt_name = name + "_wheeltags"
    wheel_tags_setting(
        name = wt_name,
        **wheel_tags
    )
    match_all.append("is_{}_true".format(wt_name))
    if marker:
        em_name = name + "_marker"
        env_marker_setting(
            name = em_name,
            expression = marker,
        )
        match_all("is_{}_true".format(em_name))

    selects.config_setting_group(
        name = name,
        match_all = match_all,
    )

def define_targets(name, selectors):
    select_map = {}
    for i, selector in enumerate(selectors):
        actual_repo = selector["actual_repo"]
        actual = "@{}//:output.zip".format(actual_repo)
        condition_name = "pick_{}_{}".format(i, actual_repo)
        gen_package_config_settings(
            name = condition_name,
            config_settings = selector["config_settings"],
            marker = selector["marker"],
            wheel_tags = selector["wheel_tags"],
        )
        select_map[condition_name] = actual

    native.alias(
        name = name,
        actual = select(select_map),
    )
