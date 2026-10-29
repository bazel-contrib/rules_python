"""Toolchain configuration shared by the `uv` module extension and WORKSPACE.

The {obj}`uv.configure` tag class and the `configure` argument of
{obj}`uv_register_toolchains` accept the same fields with the same meaning;
both are turned into per-version configurations and toolchain definitions by
the functions in this file.
"""

load("//python/private:common_labels.bzl", "labels")

def uv_toolchain_name(version, platform):
    """Return the hub toolchain name for a `uv` version and platform.

    Args:
        version: {type}`str` the `uv` version, e.g. `0.13.5`.
        platform: {type}`str` the platform target triple, e.g.
            `x86_64-unknown-linux-gnu`.

    Returns:
        {type}`str` a name usable as a repository or target name suffix.
    """
    return "{}_{}".format(
        version.replace(".", "_"),
        platform.lower().replace("-", "_"),
    )

def set_config(
        config,
        *,
        platform,
        compatible_with,
        target_settings,
        auth_patterns,
        urls = [],
        sha256 = "",
        override = False,
        **values):
    """Apply one `uv.default` or `uv.configure` entry to a configuration.

    When `platform` is given without `compatible_with`, `target_settings` or
    `urls`, the platform is removed from the configuration.

    Args:
        config: {type}`dict` the configuration to update in place; either the
            defaults or a per-version configuration.
        platform: {type}`str` the platform target triple the entry applies
            to, or empty for version-wide values.
        compatible_with: {type}`list` the constraints of `platform`. Together
            with `target_settings`, adds or replaces the platform.
        target_settings: {type}`list` the config settings of `platform`.
        auth_patterns: {type}`dict[str, str]` auth patterns merged into the
            configuration.
        urls: {type}`list[str]` the archive URLs of `platform`, which then
            bypass the release manifest.
        sha256: {type}`str` the checksum of the archive at `urls`.
        override: {type}`bool` whether values already set may be replaced.
        **values: version-wide string values (`version`, `base_url`,
            `manifest_filename`, `netrc`); empty values are ignored.
    """
    for key, value in values.items():
        if not value:
            continue

        if not override and config.get(key):
            continue

        config[key] = value

    config.setdefault("auth_patterns", {}).update(auth_patterns)
    config.setdefault("platforms", {})
    if not platform:
        if compatible_with or target_settings or urls:
            fail("`platform` name must be specified when specifying `compatible_with`, `target_settings` or `urls`")
    elif compatible_with or target_settings:
        if not override and config.get("platforms", {}).get(platform):
            return

        config["platforms"][platform] = struct(
            name = platform.replace("-", "_").lower(),
            compatible_with = compatible_with,
            target_settings = target_settings,
        )
    elif urls:
        if not override and config.get("urls", {}).get(platform):
            return

        config.setdefault("urls", {})[platform] = struct(
            sha256 = sha256,
            urls = urls,
        )
    else:
        config["platforms"].pop(platform)

def _new_version_config(defaults):
    return {
        "auth_patterns": dict(defaults.get("auth_patterns", {})),
        "base_url": defaults["base_url"],
        "manifest_filename": defaults["manifest_filename"],
        "netrc": defaults.get("netrc", ""),
        # shallow copy is enough as the values are structs and will be
        # replaced on modification
        "platforms": dict(defaults["platforms"]),
    }

def apply_configure(versions, entries, *, defaults, override):
    """Apply `uv.configure`-like entries, in order, to the per-version configs.

    Args:
        versions: {type}`dict[str, dict]` the per-version configurations to
            update, keyed by version. The shape is something like:
            ```
            {
                "1.0.0": {
                    "base_url": "",
                    "manifest_filename": "",
                    "platforms": {
                        "platform_name": struct(
                            compatible_with = [],
                            target_settings = [],
                        ),
                    },
                    "urls": {
                        "platform_name": struct(urls = [], sha256 = ""),
                    },
                },
            }
            ```
        entries: {type}`list[struct]` the entries to apply. Each has the
            fields of the {obj}`uv.configure` tag class: `version`,
            `base_url`, `manifest_filename`, `platform`, `compatible_with`,
            `target_settings`, `urls`, `sha256`, `netrc` and `auth_patterns`.
            An entry without `version` applies to the version of the previous
            entry, or to the default version.
        defaults: {type}`dict` the defaults for new versions: `version`,
            `base_url`, `manifest_filename`, `platforms` and optionally
            `netrc` and `auth_patterns`.
        override: {type}`bool` whether the entries may replace values that
            are already set.

    Returns:
        {type}`dict[str, dict]` the updated `versions`.
    """
    last_version = None
    for tag in entries:
        last_version = tag.version or last_version or defaults["version"]
        specific_config = versions.setdefault(
            last_version,
            _new_version_config(defaults),
        )

        set_config(
            specific_config,
            base_url = tag.base_url,
            manifest_filename = tag.manifest_filename,
            platform = tag.platform,
            compatible_with = tag.compatible_with,
            target_settings = tag.target_settings,
            sha256 = tag.sha256,
            urls = tag.urls,
            override = override,
            netrc = tag.netrc,
            auth_patterns = tag.auth_patterns,
        )
    return versions

def define_toolchains(
        *,
        hub_name,
        versions,
        uv_repository,
        hub_repo,
        toolchain_type,
        resolve_sources):
    """Create the `uv` repositories and the toolchain hub for `versions`.

    Args:
        hub_name: {type}`str` the name of the hub repository.
        versions: {type}`dict[str, dict]` the per-version configurations; see
            {obj}`apply_configure`.
        uv_repository: the repository rule used to download `uv`.
        hub_repo: the hub repo factory function to use.
        toolchain_type: {type}`str` the toolchain type of the toolchains.
        resolve_sources: {type}`callable` called with `version`, `config` and
            `auth` keyword arguments for a version without explicit `urls`.
            It returns the download `urls` and `sha256` keyed by platform,
            e.g. from the release manifest; platforms it omits get no
            toolchain.

    Returns:
        The result of `hub_repo`. Mainly used for tests.
    """
    if not versions:
        return hub_repo(
            name = hub_name,
            toolchain_type = toolchain_type,
            toolchain_names = ["none"],
            toolchain_implementations = {
                # NOTE @aignas 2025-02-24: the label to the toolchain can be anything
                "none": labels.NONE,
            },
            toolchain_compatible_with = {
                "none": ["@platforms//:incompatible"],
            },
            toolchain_target_settings = {},
        )

    toolchain_names = []
    toolchain_implementations = {}
    toolchain_compatible_with_by_toolchain = {}
    toolchain_target_settings = {}
    for version, config in versions.items():
        platforms = config["platforms"]

        # Use the manually specified urls
        sources = {
            platform: src
            for platform, src in config.get("urls", {}).items()
            if src.urls
        }
        auth = {
            "auth_patterns": config.get("auth_patterns"),
            "netrc": config.get("netrc"),
        }
        auth = {k: v for k, v in auth.items() if v}

        # Or fallback to fetching them from GH manifest file
        # Example file: https://github.com/astral-sh/uv/releases/download/0.6.3/dist-manifest.json
        if not sources:
            sources = resolve_sources(version = version, config = config, auth = auth)

        for platform_name, platform in platforms.items():
            if platform_name not in sources:
                continue

            toolchain_name = uv_toolchain_name(version, platform_name)
            uv_repository_name = "{}_{}".format(hub_name, toolchain_name)
            uv_repository(
                name = uv_repository_name,
                version = version,
                platform = platform_name,
                urls = sources[platform_name].urls,
                sha256 = sources[platform_name].sha256,
                **auth
            )

            toolchain_names.append(toolchain_name)
            toolchain_implementations[toolchain_name] = "@{}//:uv_toolchain".format(
                uv_repository_name,
            )
            toolchain_compatible_with_by_toolchain[toolchain_name] = [
                str(label)
                for label in platform.compatible_with
            ]
            if platform.target_settings:
                toolchain_target_settings[toolchain_name] = [
                    str(label)
                    for label in platform.target_settings
                ]

    return hub_repo(
        name = hub_name,
        toolchain_type = toolchain_type,
        toolchain_names = toolchain_names,
        toolchain_implementations = toolchain_implementations,
        toolchain_compatible_with = toolchain_compatible_with_by_toolchain,
        toolchain_target_settings = toolchain_target_settings,
    )
