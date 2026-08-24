"""Macro to generate all of the targets present in a {obj}`whl_library`."""

load("//python:py_library.bzl", "py_library")
load("//python/private:normalize_name.bzl", "normalize_name")
load(":env_marker_setting.bzl", "env_marker_setting")
load(
    ":labels.bzl",
    "DATA_LABEL",
    "DIST_INFO_LABEL",
    "EXTRACTED_WHEEL_FILES",
    "PY_LIBRARY_IMPL_LABEL",
    "PY_LIBRARY_PUBLIC_LABEL",
    "PY_SRCS_LABEL",
    "WHEEL_FILE",
    "WHEEL_FILE_IMPL_LABEL",
    "WHEEL_FILE_PUBLIC_LABEL",
)
load(":pep508_deps.bzl", "deps")

def whl_library_deps_targets(
        *,
        name = None,
        repo,
        aliases = None,
        metadata_name,
        requires_dist = [],
        extras = [],
        include = [],
        group_deps = [],
        group_name = None,
        dep_template,
        tags = [],
        visibility = ["//visibility:public"],
        native = native,
        rules = struct(
            py_library = py_library,
            env_marker_setting = env_marker_setting,
        )):
    """Create all of the whl_library targets.

    Args:
        name: {type}`str` The wheel filename
        metadata_name: {type}`str` The package name as written in wheel
            `METADATA`.
        group_deps: {type}`list[str]` names of fellow members of the group (if
            any). These will be excluded from generated deps lists so as to avoid
            direct cycles. These dependencies will be provided at runtime by the
            group rules which wrap this library and its fellows together.
        requires_dist: {type}`list[str]` The list of `Requires-Dist` values from
            the whl `METADATA`. Optional because some packages don't have them.
        extras: {type}`list[str]` The list of requested extras. This essentially
            includes extra transitive dependencies in the final targets
            depending on the wheel `METADATA`. Optional because some packages
            don't request them.
        include: {type}`list[str]` The list of packages to include.
        group_name: {type}`str | None` name of the dependency group (if any).
        dep_template: {type}`str | None` The dep_template to use.
        tags: {type}`list[str]` The tags set on the targets.
        repo: {type}`str | Label | None` The BUILD.bazel label to the parent
            repo that has the sources. If none, then will take the targets from
            the current dir.
        aliases: {type}`dict[str, str] | None` The list of aliases to create in
            the parent repo. If None, will create the default values. Empty list
            means no aliases.
        visibility: {type}`list[str]` The visibility of the targets.
        native: {type}`native` The native struct for overriding in tests.
        rules: {type}`struct` A struct with references to rules for creating
            targets.
    """
    repo_label = Label(repo).same_package_label if repo else (lambda x: x)
    if aliases == None:
        aliases = {
            EXTRACTED_WHEEL_FILES: repo_label(EXTRACTED_WHEEL_FILES),
            DIST_INFO_LABEL: repo_label(DIST_INFO_LABEL),
            DATA_LABEL: repo_label(DATA_LABEL),
        }

    # If this library is a member of a group, its public label aliases need to
    # point to the group implementation rule not the implementation rules. We
    # also need to mark the implementation rules as visible to the group
    # implementation.
    if group_name and "//:" in dep_template:
        # This is the legacy behaviour where the group library is outside the hub repo
        #
        # It is expected to disappear when we drop WORKSPACE or drop the vendoring of
        # pip_parse `requirements.bzl` in WORKSPACE. The alternative would be to add
        # another argument to the macro, but it is already full of arguments.
        label_tmpl = dep_template.format(
            name = "_config",
            target = normalize_name(group_name) + "_{}",
        ).replace(
            "//:",
            "//_groups:",
        )
        aliases = aliases | {
            PY_LIBRARY_PUBLIC_LABEL: label_tmpl.format(PY_LIBRARY_PUBLIC_LABEL),
            WHEEL_FILE_PUBLIC_LABEL: label_tmpl.format(WHEEL_FILE_PUBLIC_LABEL),
        }
        impl_vis = [dep_template.format(
            name = "_config",
            target = "__pkg__",
        ).replace(
            "//:",
            "//_groups:",
        )]

        py_library_label = PY_LIBRARY_IMPL_LABEL
        whl_file_label = WHEEL_FILE_IMPL_LABEL
    else:
        py_library_label = PY_LIBRARY_PUBLIC_LABEL
        whl_file_label = WHEEL_FILE_PUBLIC_LABEL
        if group_name:
            impl_vis = [dep_template.format(name = "", target = "__subpackages__")]
        else:
            impl_vis = visibility

    if not requires_dist:
        # If the package is in a group but has no deps, we still need the public labels to
        # point at the srcs targets so that the group implementation can use them. We don't
        # need any of the extra targets, so just create the aliases.
        aliases = aliases | {
            py_library_label: repo_label(PY_SRCS_LABEL),
            whl_file_label: repo_label(WHEEL_FILE),
        }

    for alias, actual in aliases.items():
        native.alias(
            name = alias,
            actual = actual,
            visibility = visibility,
        )

    if not requires_dist:
        # If there are extras, then they will be visible in requires_dist.
        return

    package_deps = _parse_requires_dist(
        name = metadata_name,
        requires_dist = requires_dist,
        excludes = group_deps,
        extras = extras,
        include = include,
    )

    _config_settings(
        dependencies_with_markers = package_deps.deps_select,
        rules = rules,
        visibility = ["//visibility:private"],
    )

    if hasattr(native, "filegroup"):
        # We include the whl file as srcs so that `$(location :whl)` expands to the whl file.
        # The transitive dependencies are available via the `data` attribute.
        native.filegroup(
            name = whl_file_label,
            srcs = [repo_label(WHEEL_FILE)],
            data = _deps(
                deps = [],
                package_deps = package_deps,
                tmpl = dep_template.format(name = "{}", target = WHEEL_FILE_PUBLIC_LABEL),
            ),
            visibility = impl_vis,
        )

    if hasattr(rules, "py_library"):
        rules.py_library(
            name = py_library_label,
            # We include as srcs to ensure that the (locations :pkg) works as expected.
            srcs = [repo_label(PY_SRCS_LABEL)],
            deps = _deps(
                # We include as deps, so that `PyInfo` and friends (e.g. `pyi_srcs`) get
                # propagated. Just passing the target as `srcs` is not enough to propagate
                # `pyi_srcs`, see `tests/base_rules/py_library`.
                deps = [repo_label(PY_SRCS_LABEL)],
                package_deps = package_deps,
                tmpl = dep_template.format(name = "{}", target = PY_LIBRARY_PUBLIC_LABEL),
            ),
            # Disable precompilation on this wrapper target to prevent duplicate
            # pyc generation; the underlying PY_SRCS_LABEL target handles it.
            precompile = "disabled",
            tags = tags,
            visibility = impl_vis,
        )

def _parse_requires_dist(
        *,
        name,
        requires_dist,
        excludes,
        include,
        extras):
    return deps(
        name = normalize_name(name),
        requires_dist = requires_dist,
        excludes = excludes,
        include = include,
        extras = extras,
    )

def _config_settings(dependencies_with_markers, rules, **kwargs):
    """Generate config settings for the targets.

    Args:
        dependencies_with_markers: {type}`dict[str, str]` The markers to evaluate by
            each dep.
        rules: used for testing
        **kwargs: Extra kwargs to pass to the rule.
    """
    for dep, expression in dependencies_with_markers.items():
        rules.env_marker_setting(
            name = "include_{}".format(dep),
            expression = expression,
            **kwargs
        )

def _deps(deps, package_deps, tmpl):
    deps = [] + deps + [tmpl.format(d) for d in sorted(package_deps.deps)]

    for dep in package_deps.deps_select:
        deps = deps + select({
            ":is_include_{}_true".format(dep): [tmpl.format(dep)],
            "//conditions:default": [],
        })

    return deps
