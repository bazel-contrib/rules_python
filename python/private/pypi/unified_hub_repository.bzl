"""Repository rule for creating the canonical Unified PyPI Hub."""

load("//python/private:text_util.bzl", "render")

_ROOT_BUILD_TMPL = """\
package(default_visibility = ["//visibility:public"])

{config_settings}
"""

_CONFIG_SETTING_TMPL = """\
config_setting(
    name = "_is_pypi_hub_{hub_name}",
    flag_values = {{"@rules_python//python/config_settings:pypi_hub": "{hub_name}"}},
)
"""

_PKG_BUILD_TMPL = """\
load("@rules_python//python/private/pypi:missing_package.bzl", "missing_package_error")

package(default_visibility = ["//visibility:public"])

{missing_errors}

{aliases}
"""

_MISSING_ERR_TMPL = """\
missing_package_error(
    name = "{err_name}",
    hub_name = "{hub_name}",
    package_name = "{pkg_name}",
)
"""

_ALIAS_TMPL = """\
alias(
    name = "{alias_name}",
    actual = {actual},
)
"""

_STANDARD_ALIASES = [
    "pkg",
    "whl",
    "data",
    "dist_info",
    "extracted_wheel_files",
]

def _unified_hub_repository_impl(rctx):
    hubs = rctx.attr.hubs
    default_hub = rctx.attr.default_hub
    if not default_hub:
        fail("default_hub must be specified.")

    # 1. Generate Root BUILD.bazel with shared config settings
    config_settings = "\n".join([
        _CONFIG_SETTING_TMPL.format(hub_name = hub)
        for hub in hubs
    ])
    rctx.file("BUILD.bazel", _ROOT_BUILD_TMPL.format(config_settings = config_settings))

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
        all_aliases = _STANDARD_ALIASES + sorted(extra_aliases.keys())

        missing_errors = {}
        aliases_str = []

        # Main apparent package target delegates to :pkg
        aliases_str.append(_ALIAS_TMPL.format(alias_name = pkg_name, actual = '":pkg"'))

        for alias_name in all_aliases:
            select_map = {}
            for hub in hubs:
                is_supported = (alias_name in _STANDARD_ALIASES and hub in pkg_hubs) or \
                               (alias_name not in _STANDARD_ALIASES and hub in extra_aliases.get(alias_name, []))

                if is_supported:
                    select_map["//:_is_pypi_hub_" + hub] = "@{hub}//{pkg}:{alias}".format(
                        hub = hub,
                        pkg = pkg_name,
                        alias = alias_name,
                    )
                else:
                    err_target = "_missing_{alias}_in_{hub}".format(alias = alias_name, hub = hub)
                    if err_target not in missing_errors:
                        missing_errors[err_target] = _MISSING_ERR_TMPL.format(
                            err_name = err_target,
                            hub_name = hub,
                            pkg_name = pkg_name if alias_name in _STANDARD_ALIASES else (pkg_name + ":" + alias_name),
                        )
                    select_map["//:_is_pypi_hub_" + hub] = ":{}".format(err_target)

            # //conditions:default fallback
            default_supported = (alias_name in _STANDARD_ALIASES and default_hub in pkg_hubs) or \
                                (alias_name not in _STANDARD_ALIASES and default_hub in extra_aliases.get(alias_name, []))

            if default_supported:
                select_map["//conditions:default"] = "@{hub}//{pkg}:{alias}".format(
                    hub = default_hub,
                    pkg = pkg_name,
                    alias = alias_name,
                )
            else:
                err_target = "_missing_{alias}_in_{hub}".format(alias = alias_name, hub = default_hub)
                if err_target not in missing_errors:
                    missing_errors[err_target] = _MISSING_ERR_TMPL.format(
                        err_name = err_target,
                        hub_name = default_hub,
                        pkg_name = pkg_name if alias_name in _STANDARD_ALIASES else (pkg_name + ":" + alias_name),
                    )
                select_map["//conditions:default"] = ":{}".format(err_target)

            aliases_str.append(_ALIAS_TMPL.format(
                alias_name = alias_name,
                actual = "select(%s)" % render.dict(select_map),
            ))

        rctx.file(
            pkg_name + "/BUILD.bazel",
            _PKG_BUILD_TMPL.format(
                missing_errors = "\n".join(missing_errors.values()),
                aliases = "\n".join(aliases_str),
            ),
        )

unified_hub_repository = repository_rule(
    implementation = _unified_hub_repository_impl,
    attrs = {
        "default_hub": attr.string(
            mandatory = True,
            doc = "The fallback PyPI hub to use when no hub is requested.",
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
    },
    doc = "Private repository rule creating the canonical automatic Unified PyPI Hub.",
)
