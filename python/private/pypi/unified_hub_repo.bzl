"""Repository rule for creating the Unified PyPI Hub."""

load("//python/private:normalize_name.bzl", "normalize_name")
load("//python/private:text_util.bzl", "render")

_ROOT_BUILD_TMPL = """\
load("@rules_python//python/private/pypi:unified_hub_setup.bzl", "define_venv_flag_config_settings")

package(default_visibility = ["//visibility:public"])

# Ensure the `requirements.bzl` source can be accessed by stardoc, since users load() from it
exports_files(["requirements.bzl"])

define_venv_flag_config_settings(
    name = "venv_config_settings",
    hubs = {hubs},
)
"""

_PKG_BUILD_TMPL = """\
load("@rules_python//python/private/pypi:unified_hub_setup.bzl", "define_pypi_package_targets")

package(default_visibility = ["//visibility:public"])

define_pypi_package_targets(
    name = "{pkg_name}",
    default_hub = {default_hub},
    extra_aliases = {extra_aliases},
    hubs = {hubs},
    pkg_hubs = {pkg_hubs},
)
"""

def _unified_hub_repo_impl(rctx):
    hubs = rctx.attr.hubs
    default_hub = rctx.attr.default_hub or None

    # 1. Generate Root BUILD.bazel with shared config settings
    rctx.file(
        "BUILD.bazel",
        _ROOT_BUILD_TMPL.format(hubs = hubs),
    )

    # 2. Organize extra aliases by package
    extra_aliases_by_pkg = {}
    for qual_alias, alias_hubs in rctx.attr.extra_aliases.items():
        if ":" not in qual_alias:
            fail("extra_aliases keys must be in 'pkg:alias' format.")
        pkg, alias = qual_alias.split(":", 1)
        extra_aliases_by_pkg.setdefault(pkg, {})[alias] = alias_hubs

    # 3. Generate package subpackages
    for pkg_name, pkg_hubs in rctx.attr.packages.items():
        extra_aliases = extra_aliases_by_pkg.get(pkg_name, {})
        rctx.file(
            pkg_name + "/BUILD.bazel",
            _PKG_BUILD_TMPL.format(
                default_hub = render.str(default_hub),
                extra_aliases = extra_aliases,
                hubs = hubs,
                pkg_hubs = pkg_hubs,
                pkg_name = pkg_name,
            ),
        )

    # 4. Generate requirements.bzl with the same API as a concrete hub's, so a
    # hub renamed away from the reserved "pypi" name keeps its
    # `load("@pypi//:requirements.bzl", "requirement")` users working. The
    # macros return labels in this repo, so they route through the venv flag
    # like any other `@pypi//<pkg>` label. The `all_*` lists are fixed at
    # loading time, before the venv flag is known, so they name the default
    # hub's packages.
    #
    # NOTE: we are using the canonical name with the double '@' in order to
    # always uniquely identify a repository, as the labels are being passed as
    # a string and the resolution of the label happens at the call-site of the
    # `requirement`, et al. macros.
    macro_tmpl = "@@{name}//{{}}:{{}}".format(name = rctx.attr.name)
    default_packages = sorted([
        pkg_name
        for pkg_name, pkg_hubs in rctx.attr.packages.items()
        if default_hub in pkg_hubs
    ])
    rctx.template("requirements.bzl", rctx.attr._requirements_bzl_template, substitutions = {
        "%%ALL_DATA_REQUIREMENTS%%": render.list([
            macro_tmpl.format(p, "data")
            for p in default_packages
        ]),
        "%%ALL_REQUIREMENTS%%": render.list([
            macro_tmpl.format(p, "pkg")
            for p in default_packages
        ]),
        "%%ALL_WHL_REQUIREMENTS_BY_PACKAGE%%": render.dict({
            p: macro_tmpl.format(p, "whl")
            for p in default_packages
        }),
        "%%MACRO_TMPL%%": macro_tmpl,
    })

unified_hub_repo = repository_rule(
    implementation = _unified_hub_repo_impl,
    attrs = {
        "default_hub": attr.string(
            doc = "The PyPI hub to use when no other hub's conditions match.",
        ),
        "extra_aliases": attr.string_list_dict(
            doc = "Dictionary mapping 'package:alias' to a list of hubs that support it.",
        ),
        "hubs": attr.string_list(
            mandatory = True,
            doc = "List of all concrete PyPI hub names.",
        ),
        "packages": attr.string_list_dict(
            mandatory = True,
            doc = "Dictionary mapping package names to a list of hubs that contain them.",
        ),
        "_requirements_bzl_template": attr.label(
            default = ":requirements.bzl.tmpl.bzlmod",
        ),
    },
    doc = "Private repository rule creating the automatic Unified PyPI Hub.",
)

def unified_workspace_hub_repo(name, hubs, default_hub = None, extra_aliases = {}):
    """Creates a Unified PyPI Hub repository for WORKSPACE mode by loading requirements from hubs.

    Args:
        name: Name of the repository rule (e.g. "pypi").
        hubs: Dict mapping hub name to its `all_requirements` list or dict.
              e.g. {"dev_pip": dev_pip_requirements, "pypi_alpha": pypi_alpha_requirements}
        default_hub: Optional default hub name.
        extra_aliases: Dictionary mapping 'package:alias' to a list of hubs that support it.
    """
    packages = {}
    for hub_name, req_map in hubs.items():
        req_list = req_map.keys() if type(req_map) == type({}) else req_map
        for req in req_list:
            pkg_name = req.split("//")[-1].split(":")[0]
            norm_pkg = normalize_name(pkg_name)
            if norm_pkg not in packages:
                packages[norm_pkg] = []
            if hub_name not in packages[norm_pkg]:
                packages[norm_pkg].append(hub_name)

    unified_hub_repo(
        name = name,
        default_hub = default_hub,
        extra_aliases = extra_aliases,
        hubs = sorted(hubs.keys()),
        packages = packages,
    )
