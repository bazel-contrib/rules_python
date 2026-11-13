"""Macro to generate all of the targets present in a {obj}`whl_library`."""

load("//python:py_library.bzl", "py_library")
load("//python/private:normalize_name.bzl", "normalize_name")
load(":env_marker_setting.bzl", "env_marker_setting")
load(
    ":labels.bzl",
    "DATA_LABEL",
    "DIST_INFO_LABEL",
    "EXTRACTED_WHEEL_FILES",
    "PY_LIBRARY_PUBLIC_LABEL",
    "PY_SRCS_LABEL",
    "WHEEL_FILE",
    "WHEEL_FILE_PUBLIC_LABEL",
    "extra_label",
    "group_member",
)
load(":missing_package.bzl", "missing_extra_error")
load(":pep508_deps.bzl", "deps")

def whl_library_deps_targets(
        *,
        name = None,
        repo,
        aliases = None,
        metadata_name,
        requires_dist = [],
        provides_extra = [],
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
            missing_extra_error = missing_extra_error,
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
        provides_extra: {type}`list[str]` The list of extras that the package
            provides. For each extra the `[<extra>]` target is created
            that includes the package and the dependencies of that extra.
        include: {type}`list[str] | dict[str, list[str] | None]` The list
            of packages to include. If it is a dict, then the values are the
            extras of each package that are available in the hub and the
            dependencies on the extras that are not available will fail the
            build with a helpful message.
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

    # The members of the group are the packages, e.g. `foo`, or the extras of
    # the packages, e.g. `foo[bar]`. Only the targets of the members are part
    # of the group and they do not depend on the other members to avoid cycles.
    self_name = normalize_name(metadata_name)
    members = {group_member(m): None for m in group_deps} if group_name else {}
    is_member = lambda extra: (
        "{}[{}]".format(self_name, extra) if extra else self_name
    ) in members

    # If this library is a member of a group, its public label aliases need to
    # point to the group implementation rule not the implementation rules. We
    # also need to mark the implementation rules as visible to the group
    # implementation.
    group_label = None
    if group_name and "//:" in dep_template:
        # This is the legacy behaviour where the group library is outside the hub repo
        #
        # It is expected to disappear when we drop WORKSPACE or drop the vendoring of
        # pip_parse `requirements.bzl` in WORKSPACE. The alternative would be to add
        # another argument to the macro, but it is already full of arguments.
        group_label = dep_template.format(
            name = "_config",
            target = normalize_name(group_name) + "_{}",
        ).replace(
            "//:",
            "//_groups:",
        )
        impl_vis = [dep_template.format(
            name = "_config",
            target = "__pkg__",
        ).replace(
            "//:",
            "//_groups:",
        )]
    elif group_name:
        impl_vis = [dep_template.format(name = "", target = "__subpackages__")]
    else:
        impl_vis = visibility

    def _name(extra, public):
        # In the legacy mode the targets of the members are implementation
        # targets and the public targets are aliases to the group.
        prefix = "_" if group_label and is_member(extra) else ""
        return prefix + (extra_label(extra) if extra else public)

    def _visibility(extra):
        # In the legacy mode the targets that are not members are public.
        return visibility if group_label and not is_member(extra) else impl_vis

    # Create targets for every extra that the package provides, so that the hub
    # can select only the extras that are requested on each platform without
    # passing the extras to this repository.
    extras_targets = [""] + sorted({normalize_name(e): None for e in provides_extra})
    whl_file_label = _name("", WHEEL_FILE_PUBLIC_LABEL)

    if group_label:
        for extra in extras_targets:
            if is_member(extra):
                aliases[extra_label(extra) if extra else PY_LIBRARY_PUBLIC_LABEL] = group_label.format(PY_LIBRARY_PUBLIC_LABEL)
        if is_member(""):
            aliases[WHEEL_FILE_PUBLIC_LABEL] = group_label.format(WHEEL_FILE_PUBLIC_LABEL)

    if not requires_dist:
        # If the package is in a group but has no deps, we still need the labels to point at
        # the srcs targets so that the group implementation can use them.
        aliases[whl_file_label] = repo_label(WHEEL_FILE)
        for extra in extras_targets:
            aliases[_name(extra, PY_LIBRARY_PUBLIC_LABEL)] = repo_label(PY_SRCS_LABEL)

    for alias, actual in aliases.items():
        native.alias(
            name = alias,
            actual = actual,
            visibility = visibility,
        )

    if not requires_dist:
        # If there are extras, then they will be visible in requires_dist.
        return

    # The settings for the deps that are included conditionally keyed by the
    # dep and the expression.
    settings = {}

    # The dependencies on extras that are not available in the hub.
    missing_extras = {}

    def _pkg_label(dep):
        dep_name, _, extra = dep.partition("[")
        if not extra:
            return dep_template.format(name = dep_name, target = PY_LIBRARY_PUBLIC_LABEL)

        extra = extra.rstrip("]")
        available = include.get(dep_name) if type(include) == type({}) else None
        if available != None and extra not in available:
            missing_extras[dep] = (dep_name, extra)
            return ":_missing_" + dep

        return dep_template.format(name = dep_name, target = extra_label(extra))

    whl_label = lambda dep: dep_template.format(name = dep, target = WHEEL_FILE_PUBLIC_LABEL)

    if hasattr(native, "filegroup"):
        # We include the whl file as srcs so that `$(location :whl)` expands to the whl file.
        # The transitive dependencies are available via the `data` attribute. The extras
        # are not used for the whl targets, so only the packages without extras can be
        # members of the group for the whl targets.
        whl_deps = deps(
            name = self_name,
            requires_dist = requires_dist,
            include = include,
            excludes = members if is_member("") else [],
        )
        native.filegroup(
            name = whl_file_label,
            srcs = [repo_label(WHEEL_FILE)],
            data = _deps(
                deps = [],
                package_deps = whl_deps,
                conditions = _conditions(settings, whl_deps),
                label = whl_label,
            ),
            visibility = _visibility(""),
        )

    for extra in extras_targets if hasattr(rules, "py_library") else []:
        package_deps = deps(
            name = self_name,
            requires_dist = requires_dist,
            include = include,
            excludes = members if is_member(extra) else [],
            extras = [extra] if extra else [],
            keep_extras = True,
        )
        rules.py_library(
            name = _name(extra, PY_LIBRARY_PUBLIC_LABEL),
            # We include as srcs to ensure that the (locations :pkg) works as expected.
            srcs = [repo_label(PY_SRCS_LABEL)],
            deps = _deps(
                # We include as deps, so that `PyInfo` and friends (e.g. `pyi_srcs`) get
                # propagated. Just passing the target as `srcs` is not enough to propagate
                # `pyi_srcs`, see `tests/base_rules/py_library`.
                deps = [repo_label(PY_SRCS_LABEL)],
                package_deps = package_deps,
                conditions = _conditions(settings, package_deps),
                label = _pkg_label,
            ),
            # Disable precompilation on this wrapper target to prevent duplicate
            # pyc generation; the underlying PY_SRCS_LABEL target handles it.
            precompile = "disabled",
            tags = tags,
            visibility = _visibility(extra),
        )

    for (_, expression), name in settings.items():
        rules.env_marker_setting(
            name = name,
            expression = expression,
            visibility = ["//visibility:private"],
        )

    for dep, (dep_name, extra) in sorted(missing_extras.items()):
        rules.missing_extra_error(
            name = "_missing_" + dep,
            package_name = dep_name,
            extra = extra,
            required_by = metadata_name,
            visibility = ["//visibility:private"],
        )

def _conditions(settings, package_deps):
    return {
        dep: _setting_name(settings, dep, expression)
        for dep, expression in package_deps.deps_select.items()
    }

def _setting_name(settings, dep, expression):
    """Return a unique name for the setting evaluating the expression for the dep.

    The first expression for a dep is named `include_<dep>` and any different
    expressions for the same dep get a numeric suffix.
    """
    key = (dep, expression)
    if key not in settings:
        n = len([d for d, _ in settings if d == dep])
        settings[key] = "include_{}".format(dep) + ("_{}".format(n + 1) if n else "")

    return settings[key]

def _deps(deps, package_deps, conditions, label):
    deps = [] + deps + [label(d) for d in sorted(package_deps.deps)]

    for dep in package_deps.deps_select:
        deps = deps + select({
            ":is_{}_true".format(conditions[dep]): [label(dep)],
            "//conditions:default": [],
        })

    return deps
