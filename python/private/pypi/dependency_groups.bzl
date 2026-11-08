"""Select PyPI packages using pyproject.toml dependency groups."""

load("@bazel_skylib//lib:types.bzl", "types")
load("//python/private:normalize_name.bzl", "normalize_name")
load(":pep508_requirement.bzl", "requirement")

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
        {type}`struct` with the attributes:
          * `packages`: {type}`list[str]` the sorted normalized package names.
          * `all`: {type}`bool` whether all of the packages including the
            transitive dependencies should be selected, i.e. `"*"` and
            `"transitive"` were given.
    """
    groups = {"default": pyproject.dependencies}
    for name, reqs in pyproject.optional_dependencies.items():
        groups["optional:" + normalize_name(name)] = reqs
    for name, reqs in _expand_dependency_groups(pyproject.dependency_groups, _fail).items():
        groups["group:" + name] = reqs

    if "transitive" in specs:
        if "*" not in specs:
            _fail("The 'transitive' dependency group specifier is only supported together with '*', which selects all of the packages, got: {}".format(specs))
        return struct(packages = [], all = True)

    selected = {}
    for spec in specs:
        keys = _match(spec, groups)
        if not keys:
            _fail("Unknown dependency group '{}'. Available groups: {}".format(
                spec,
                ", ".join(sorted(groups)),
            ))
        for key in keys:
            selected[key] = None

    # A self reference like `my-project[test]` selects the optional
    # dependencies, but only one level deep.
    project = normalize_name(pyproject.name or "")
    packages = {}
    for key in selected:
        for req in groups[key]:
            req = requirement(req)
            if req.name_ != project:
                packages[req.name_] = None
                continue
            for extra in req.extras:
                for r in groups.get("optional:" + extra, []):
                    packages[requirement(r).name_] = None

    return struct(packages = sorted(packages), all = False)

def _match(spec, groups):
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
        dependency_groups: {type}`dict[str, list]` the `[dependency-groups]`
            table.
        _fail: {type}`callable` the failure function.

    Returns:
        {type}`dict[str, list[str]]` normalized group names mapped to their
        requirement strings.
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
                    _fail("Unknown dependency group '{}' included from '{}'".format(include, name))
                    return {}
                if include not in expanded:
                    reqs = None
                    break
                reqs.extend(expanded[include])

            if reqs != None:
                expanded[name] = reqs

    if len(expanded) != len(groups):
        _fail("Cyclic dependency group includes: {}".format(
            ", ".join(sorted([name for name in groups if name not in expanded])),
        ))
    return expanded
