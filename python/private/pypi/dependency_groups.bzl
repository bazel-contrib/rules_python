"""Select PyPI packages using pyproject.toml dependency groups."""

load("@bazel_skylib//lib:types.bzl", "types")
load("//python/private:normalize_name.bzl", "normalize_name")
load(":pep508_requirement.bzl", "requirement")

# The limit for processing the groups selected by the self references, e.g.
# `my-project[test]`. A group is processed once for each different set of
# markers that it is selected with.
_MAX_SELF_REFERENCES = 10000

def select_dependency_groups(pyproject, specs, _fail = fail):
    """Select the packages named by the given dependency group specifiers.

    Supported specifiers are:

      * `"default"`: the `[project] dependencies`.
      * `"optional:<name>"`: a `[project.optional-dependencies]` entry.
      * `"group:<name>"`: a PEP 735 `[dependency-groups]` entry.
      * `"optional:*"` and `"group:*"`: all entries of the table.
      * `"*"`: all of the above.
      * `"<name>"`: a dependency group, or an optional dependency group if
        there is no dependency group with that name.
      * `"transitive"`: only supported together with `"*"` and selects all
        of the packages, including the transitive dependencies.

    Args:
        pyproject: {type}`struct` returned by `read_pyproject`.
        specs: {type}`list[str]` the specifiers.
        _fail: {type}`callable` the failure function, mainly for testing.

    Returns:
        {type}`struct | None` with the attributes:
          * `packages`: {type}`list[str]` the sorted normalized package names.
          * `all`: {type}`bool` whether all of the packages including the
            transitive dependencies should be selected, i.e. `"*"` and
            `"transitive"` were given.
          * `extras`: {type}`dict[str, dict[tuple[str], list[str]]]` the
            normalized package names mapped to the extras that the selected
            requirements request, e.g. `requests[socks]`. The extras are
            keyed by the environment markers that all need to be true for
            the extras to be requested, e.g. `("sys_platform == 'win32'",)`
            or an empty tuple if there are no markers. When `all` is set,
            the extras of all of the groups are returned.
        Returns `None` on failure.
    """
    groups = {"default": pyproject.dependencies}
    for name, reqs in pyproject.optional_dependencies.items():
        groups["optional:" + normalize_name(name)] = reqs
    expanded = _expand_dependency_groups(pyproject.dependency_groups, _fail)
    if expanded == None:
        return None
    for name, reqs in expanded.items():
        groups["group:" + name] = reqs

    select_all = "transitive" in specs
    if select_all:
        if "*" not in specs:
            _fail("The 'transitive' dependency group specifier is only supported together with '*', which selects all of the packages, got: {}".format(
                specs,
            ))
            return None

        # All of the packages are selected, but the extras are only known
        # from the groups.
        specs = ["*"]

    selected = {}
    for spec in specs:
        keys = _match(spec, groups)

        # A wildcard matches nothing when its table is empty or missing.
        if not keys and spec not in ("*", "optional:*", "group:*"):
            _fail("Unknown dependency group '{}'. Available groups: {}".format(
                spec,
                ", ".join(sorted(groups)),
            ))
            return None
        for key in keys:
            selected[key] = None

    # A self reference like `my-project[test]` selects the optional
    # dependencies, including nested composite extras.
    #
    # The groups are queued together with the markers of the self references
    # that selected them, because the requirements of such groups are only
    # requested when the markers are true. A group is processed again if it is
    # selected with markers that are not known to be stricter than the ones
    # that it was processed with.
    project = normalize_name(pyproject.name or "")
    packages = {}
    extras = {}
    processed = {}
    queue = [(key, ()) for key in selected]
    for _ in range(_MAX_SELF_REFERENCES):
        if not queue:
            break
        key, markers = queue.pop(0)
        if _is_processed(processed.setdefault(key, []), markers):
            continue
        processed[key].append(markers)
        for req in groups[key]:
            req = requirement(req)
            req_markers = _add_marker(markers, req.marker)
            if req.name_ != project:
                packages[req.name_] = None
                if req.extras:
                    pkg_extras = extras.setdefault(req.name_, {}).setdefault(req_markers, {})
                    for extra in req.extras:
                        pkg_extras[extra] = None
                continue
            for extra in req.extras:
                opt_key = "optional:" + extra
                if opt_key in groups:
                    queue.append((opt_key, req_markers))

    if queue:
        _fail("Too many self references with different markers in the dependency groups of '{}'".format(
            pyproject.name,
        ))
        return None

    return struct(
        # list[str]: sorted normalized package names selected by `specs`.
        packages = [] if select_all else sorted(packages),
        # bool: True when all packages including transitive ones are selected.
        all = select_all,
        # dict[str, dict[tuple[str], list[str]]]: the extras of the packages
        # keyed by the markers that need to be true.
        extras = {
            name: {
                markers: sorted(pkg_extras)
                for markers, pkg_extras in sorted(by_markers.items())
            }
            for name, by_markers in sorted(extras.items())
        },
    )

def _add_marker(markers, marker):
    if not marker or marker in markers:
        return markers
    return tuple(sorted(markers + (marker,)))

def _is_processed(processed, markers):
    """Tell if a group was already processed with the same or looser markers.

    Args:
        processed: {type}`list[tuple[str]]` the markers that the group was
            processed with.
        markers: {type}`tuple[str]` the markers to check.

    Returns:
        {type}`bool` `True` if all of the markers of a processed entry are in
        `markers`, i.e. the requirements of the group are already requested
        whenever `markers` are true.
    """
    for known in processed:
        if len([m for m in known if m in markers]) == len(known):
            return True
    return False

def _match(spec, groups):
    """Match a dependency group specifier against normalized group keys.

    Args:
        spec: {type}`str` the dependency group specifier.
        groups: {type}`dict[str, list[str]]` available groups keyed by
            prefixed group name.

    Returns:
        {type}`list[str]` matching keys in `groups`.
    """
    if spec == "*":
        return groups.keys()
    if spec in ("optional:*", "group:*"):
        prefix = spec[:-1]
        return [key for key in groups if key.startswith(prefix)]

    kind, _, name = spec.rpartition(":")
    name = normalize_name(name)
    if kind:
        candidates = [kind + ":" + name]
    elif name == "default":
        candidates = ["default"]
    else:
        candidates = ["group:" + name, "optional:" + name]

    for key in candidates:
        if key in groups:
            return [key]
    return []

def _expand_dependency_groups(dependency_groups, _fail):
    """Expand the PEP 735 `include-group` entries.

    Args:
        dependency_groups: {type}`dict[str, list[str | dict[str, str]]]` the
            `[dependency-groups]` table.
        _fail: {type}`callable` the failure function.

    Returns:
        {type}`dict[str, list[str]] | None` normalized group names mapped to
        their requirement strings, or `None` on failure.
    """
    groups = {
        normalize_name(name): items
        for name, items in dependency_groups.items()
    }

    # Each round expands at least one group unless there is a cycle.
    expanded = {}
    for _ in range(len(groups)):
        for name, items in groups.items():
            if name in expanded:
                continue

            reqs = []
            for item in items:
                if types.is_string(item):
                    reqs.append(item)
                    continue

                include = normalize_name(item.get("include-group", ""))
                if include not in groups:
                    _fail("Unknown dependency group '{}' included from '{}'".format(
                        include,
                        name,
                    ))
                    return None
                if include not in expanded:
                    reqs = None
                    break
                reqs.extend(expanded[include])

            if reqs != None:
                expanded[name] = reqs

    if len(expanded) != len(groups):
        unexpanded = [name for name in groups if name not in expanded]
        _fail("Cyclic dependency group includes: {}".format(
            ", ".join(sorted(unexpanded)),
        ))
        return None
    return expanded
