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
        {type}`dict[str, struct] | None` the configured hubs and venvs mapped
        to a struct with:
          * `hub`: {type}`str` the hub that provides the packages. For a venv
            this is different from the key.
          * `packages`: {type}`list[str]` the sorted packages that the hub
            exposes.
          * `testonly_packages`: {type}`list[str]` the sorted packages whose
            aliases are testonly. A package is testonly only if all of the
            tags that select it are testonly.

        The hubs that are not configured are not included. Returns `None` on
        failure.

        A venv is a named selection of the packages of a hub that is used
        through the unified `@pypi` hub.
    """

    # The root module wins over the owner of the hub when both configure it.
    root_modules = [mod for mod in module_ctx.modules if mod.is_root]
    root_name = root_modules[0].name if root_modules else None
    root_configured = {
        tag.hub_name: None
        for mod in root_modules
        for tag in mod.tags.configure
        if tag.venv in ("", tag.hub_name)
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
            venv = tag.venv or hub
            if not mod.is_root and mod.name != info.module_name:
                # Only the root module and the module that created the hub can
                # configure it.
                continue
            if venv == hub and not mod.is_root and hub in root_configured:
                continue
            if venv != hub:
                err = _venv_error(venv, hub, hubs = hubs, configured = configured, testonly = tag.testonly)
                if err:
                    _fail(err)
                    return None

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

            # Multiple tags for the same hub or venv are combined.
            exposed = configured.setdefault(venv, struct(hub = hub, packages = {})).packages
            for name in packages:
                # The pyproject.toml may list packages that are not in the hub,
                # e.g. tools that are not locked.
                if name in info.packages:
                    exposed[name] = exposed.get(name, True) and tag.testonly

    return {
        name: struct(
            hub = info.hub,
            packages = sorted(info.packages),
            testonly_packages = sorted([pkg for pkg, testonly in info.packages.items() if testonly]),
        )
        for name, info in configured.items()
    }

def _venv_error(venv, hub, *, hubs, configured, testonly):
    if venv in hubs:
        return "pip.configure() venv '{}' conflicts with the hub of the same name".format(venv)
    if venv in ("pypi", "auto"):
        return "pip.configure() venv name '{}' is reserved".format(venv)
    if venv in configured and configured[venv].hub != hub:
        return "pip.configure() venv '{}' is used with both hub '{}' and hub '{}'".format(
            venv,
            configured[venv].hub,
            hub,
        )
    if testonly:
        return "pip.configure() does not support `testonly` for the venv '{}', the packages are testonly only if they are testonly in the hub '{}'".format(venv, hub)
    return None
