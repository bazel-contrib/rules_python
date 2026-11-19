"""Compute the packages exposed by the hubs configured with `pip.configure`."""

load("//python/private:pyproject_utils.bzl", "read_pyproject")
load(":dependency_groups.bzl", "select_dependency_groups")

def hub_exposure(module_ctx, *, hubs, default_pyproject = None, _fail = fail):
    """Compute the packages exposed by the hubs configured with `pip.configure`.

    Args:
        module_ctx: {type}`module_ctx` the module context.
        hubs: {type}`dict[str, struct]` the hubs by name. Each struct has:
            * `module_name`: {type}`str` the module that created the hub.
            * `pyproject`: {type}`Label | None` from `pip.parse`.
            * `packages`: {type}`list[str]` the normalized names of all
              packages in the hub.
        default_pyproject: {type}`Label | None` from `pip.default`, only used
            for the hubs of the root module.
        _fail: {type}`callable` the failure function, mainly for testing.

    Returns:
        {type}`dict[str, struct] | None` the configured hubs mapped to a
        struct with:
          * `packages`: {type}`list[str]` the sorted packages that the hub
            exposes.
          * `testonly_packages`: {type}`list[str]` the sorted packages whose
            aliases are testonly. A package is testonly only if all of the
            tags that select it are testonly.

        The hubs that are not configured or that expose all of their packages
        are not included, so that they behave the same. Returns `None` on
        failure.
    """

    # The root module wins over the owner of the hub when both configure it.
    root_modules = [mod for mod in module_ctx.modules if mod.is_root]
    root_name = root_modules[0].name if root_modules else None
    root_configured = {}
    for mod in root_modules:
        for tag in mod.tags.configure:
            if tag.dependency_groups:
                root_configured[tag.hub_name] = None

    configured = {}
    exposes_all = {}
    for mod in module_ctx.modules:
        # The tags of a module are applied in order like a builder: a tag
        # without a `pyproject_toml` uses the last one set for the hub.
        last_pyproject = {}
        for tag in mod.tags.configure:
            hub = tag.hub_name
            if hub not in hubs:
                _fail("pip.configure() refers to unknown hub '{}'. Available hubs: {}".format(
                    hub,
                    ", ".join(sorted(hubs)),
                ))
                return None

            info = hubs[hub]
            if not mod.is_root and mod.name != info.module_name:
                # Only the root module and the module that created the hub can
                # configure it.
                continue
            if not mod.is_root and hub in root_configured:
                continue

            if tag.pyproject_toml:
                last_pyproject[hub] = tag.pyproject_toml
            if not tag.dependency_groups:
                # The tag does not select any packages.
                if tag.testonly:
                    _fail("pip.configure() for hub '{}' uses `testonly`, which needs the `dependency_groups` of the testonly packages".format(hub))
                    return None
                continue

            pyproject = last_pyproject.get(hub) or info.pyproject
            if not pyproject and info.module_name == root_name:
                pyproject = default_pyproject
            if not pyproject:
                _fail("pip.configure() for hub '{}' selects the dependency groups {}, which need a pyproject.toml, set `pyproject_toml` on this or an earlier `pip.configure` or on `pip.parse`".format(
                    hub,
                    tag.dependency_groups,
                ))
                return None

            selection = select_dependency_groups(
                read_pyproject(module_ctx, pyproject),
                tag.dependency_groups,
                _fail = _fail,
            )
            if selection == None:
                return None
            if selection.all:
                if tag.testonly:
                    _fail("pip.configure() for hub '{}' cannot use `testonly` when exposing all of the packages with {}".format(hub, tag.dependency_groups))
                    return None
                exposes_all[hub] = None

            # Multiple tags for the same hub are combined.
            exposed = configured.setdefault(hub, {})
            for name in selection.packages:
                # The pyproject.toml may list packages that are not in the hub,
                # e.g. tools that are not locked.
                if name in info.packages:
                    exposed[name] = exposed.get(name, True) and tag.testonly

    return {
        hub: struct(
            packages = sorted(packages),
            testonly_packages = sorted([name for name, testonly in packages.items() if testonly]),
        )
        for hub, packages in configured.items()
        if hub not in exposes_all
    }
