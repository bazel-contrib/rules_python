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
            * `exposed_packages`: {type}`list[str]` the packages that the hub
              exposes when it is not configured.
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

        The hubs that are not configured are not included. Returns `None` on
        failure.
    """

    # The root module wins over the owner of the hub when both configure it.
    root_modules = [mod for mod in module_ctx.modules if mod.is_root]
    root_name = root_modules[0].name if root_modules else None
    root_configured = {
        tag.hub_name: None
        for mod in root_modules
        for tag in mod.tags.configure
    }

    configured = {}
    for mod in module_ctx.modules:
        for tag in mod.tags.configure:
            hub = tag.hub_name
            if hub not in hubs:
                _fail("pip.configure() refers to unknown hub '{}'. Available hubs: {}".format(
                    hub,
                    ", ".join(sorted(hubs)),
                ))
                return None

            info = hubs[hub]
            if not mod.is_root and (mod.name != info.module_name or hub in root_configured):
                # Only the root module and the module that created the hub can
                # configure it.
                continue

            pyproject = (
                tag.pyproject_toml or
                info.pyproject or
                (default_pyproject if info.module_name == root_name else None)
            )
            if not pyproject:
                _fail("pip.configure() for hub '{}' requires a pyproject.toml, set `pyproject_toml` on `pip.configure` or `pip.parse`".format(hub))
                return None

            selection = select_dependency_groups(
                read_pyproject(module_ctx, pyproject),
                tag.dependency_groups,
                _fail = _fail,
            )
            if selection.all:
                packages = info.exposed_packages
            else:
                packages = selection.packages

            # Multiple tags for the same hub are combined.
            exposed = configured.setdefault(hub, {})
            for name in packages:
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
    }
