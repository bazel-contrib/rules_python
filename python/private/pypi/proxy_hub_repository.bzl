# Copyright 2026 The Bazel Authors. All rights reserved.
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

"""Repository rule for creating the canonical Unified PyPI Proxy Hub."""

load("//python/private:common_labels.bzl", "labels")
load("//python/private:text_util.bzl", "render")

_ROOT_BUILD_TMPL = """\
package(default_visibility = ["//visibility:public"])

{config_settings}
"""

_CONFIG_SETTING_TMPL = """\
config_setting(
    name = "_is_pypi_hub_{hub_name}",
    flag_values = {{"{pypi_hub_flag}": "{hub_name}"}},
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

def _impl(rctx):
    config = json.decode(rctx.attr.proxy_config)
    hubs = config["hubs"]
    default_hub = config.get("default_hub") or (hubs[0] if hubs else None)

    # 1. Generate Root BUILD.bazel with shared config settings
    config_settings = "\n".join([
        _CONFIG_SETTING_TMPL.format(
            hub_name = hub,
            pypi_hub_flag = rctx.attr._pypi_hub_flag,
        )
        for hub in hubs
    ])
    rctx.file("BUILD.bazel", _ROOT_BUILD_TMPL.format(config_settings = config_settings))

    # 2. Generate package subpackages
    for pkg_name, pkg_data in config["packages"].items():
        pkg_hubs = pkg_data["hubs"]
        extra_aliases = pkg_data.get("extra_aliases", {})
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
            default_supported = default_hub and \
                                ((alias_name in _STANDARD_ALIASES and default_hub in pkg_hubs) or
                                 (alias_name not in _STANDARD_ALIASES and default_hub in extra_aliases.get(alias_name, [])))

            if default_supported:
                select_map["//conditions:default"] = "@{hub}//{pkg}:{alias}".format(
                    hub = default_hub,
                    pkg = pkg_name,
                    alias = alias_name,
                )
            elif default_hub:
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

proxy_hub_repository = repository_rule(
    implementation = _impl,
    attrs = {
        "proxy_config": attr.string(
            mandatory = True,
            doc = "Serialized JSON string containing hubs, default_hub, and packages.",
        ),
        "_pypi_hub_flag": attr.string(
            default = labels.PYPI_HUB,
        ),
    },
    doc = "Private repository rule creating the canonical automatic Unified PyPI Hub Proxy.",
)
