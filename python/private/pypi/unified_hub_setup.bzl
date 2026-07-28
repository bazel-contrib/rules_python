"""Helper functions for setting up targets within the Unified PyPI Hub repository."""

load(
    "@rules_python//python/private/pypi:labels.bzl",
    "DATA_LABEL",
    "DIST_INFO_LABEL",
    "EXTRACTED_WHEEL_FILES",
    "PY_LIBRARY_PUBLIC_LABEL",
    "WHEEL_FILE_PUBLIC_LABEL",
)
load("@rules_python//python/private/pypi:missing_package.bzl", "missing_package_error")

def define_venv_flag_config_settings(name, hubs):
    """Defines the root config_settings for each PyPI spoke hub.

    Args:
        name: unused macro name required by buildifier.
        hubs: list of concrete hub names.
    """
    for hub in hubs:
        native.config_setting(
            name = "_is_venv_" + hub,
            flag_values = {"@rules_python//python/config_settings:venv": hub},
        )

_STANDARD_ALIASES = [
    PY_LIBRARY_PUBLIC_LABEL,
    WHEEL_FILE_PUBLIC_LABEL,
    DATA_LABEL,
    DIST_INFO_LABEL,
    EXTRACTED_WHEEL_FILES,
]

def define_pypi_package_targets(name, pkg_hubs, extra_aliases, hubs, default_hub = None):
    """Define the targets for a PyPI package in the unified PyPI hub.

    Args:
        name: normalized PyPI package name, serving as the main target name.
        pkg_hubs: list of hubs that contain this package.
        extra_aliases: dict mapping extra alias names to lists of hubs that support them.
        hubs: list of all concrete hub names.
        default_hub: the hub to use by default.
    """
    pkg_name = name

    # Main apparent package target delegates to :pkg
    native.alias(
        name = pkg_name,
        actual = ":pkg",
    )

    all_aliases = _STANDARD_ALIASES + sorted(extra_aliases.keys())
    missing_errors = {}

    for alias_name in all_aliases:
        select_map = {}
        for hub in hubs:
            is_supported = (
                (alias_name in _STANDARD_ALIASES and hub in pkg_hubs) or
                (alias_name not in _STANDARD_ALIASES and hub in extra_aliases.get(alias_name, []))
            )

            if is_supported:
                select_map["//:_is_venv_" + hub] = "@{hub}//{pkg}:{alias}".format(
                    hub = hub,
                    pkg = pkg_name,
                    alias = alias_name,
                )
            else:
                err_target = "_missing_{alias}_in_{hub}".format(alias = alias_name, hub = hub)
                if err_target not in missing_errors:
                    missing_errors[err_target] = {
                        "hub_name": hub,
                        "package_name": pkg_name if alias_name in _STANDARD_ALIASES else (pkg_name + ":" + alias_name),
                    }
                select_map["//:_is_venv_" + hub] = ":{}".format(err_target)

        # //conditions:default fallback
        default_supported = (
            default_hub and
            ((alias_name in _STANDARD_ALIASES and default_hub in pkg_hubs) or
             (alias_name not in _STANDARD_ALIASES and default_hub in extra_aliases.get(alias_name, [])))
        )

        if default_supported:
            select_map["//conditions:default"] = "@{hub}//{pkg}:{alias}".format(
                hub = default_hub,
                pkg = pkg_name,
                alias = alias_name,
            )
        else:
            err_target = "_missing_{alias}_in_default".format(alias = alias_name)
            if err_target not in missing_errors:
                missing_errors[err_target] = {
                    "hub_name": default_hub or "",
                    "package_name": pkg_name if alias_name in _STANDARD_ALIASES else (pkg_name + ":" + alias_name),
                }
            select_map["//conditions:default"] = ":{}".format(err_target)

        native.alias(
            name = alias_name,
            actual = select(select_map),
        )

    # Generate missing package error targets
    for err_name, err_args in missing_errors.items():
        missing_package_error(
            name = err_name,
            **err_args
        )
