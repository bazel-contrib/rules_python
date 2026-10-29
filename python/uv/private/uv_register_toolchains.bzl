"""Create and register `uv` toolchains from a WORKSPACE file."""

load("@bazel_skylib//lib:types.bzl", "types")
load(":toolchain_types.bzl", "UV_TOOLCHAIN_TYPE")
load(":uv_defaults.bzl", "DEFAULT_PLATFORMS", "DEFAULT_VERSION")
load(":uv_repository.bzl", "uv_repository")
load(":uv_toolchain_config.bzl", "apply_configure", "define_toolchains")
load(":uv_toolchains_repo.bzl", "uv_toolchains_repo")

# The fields of a `configure` entry, with their empty values. They are the
# attributes of the `uv.configure` tag class except `base_url` and
# `manifest_filename`, which belong to `uv_toolchains_manifest`.
_ENTRY_FIELDS = {
    "auth_patterns": {},
    "compatible_with": [],
    "netrc": "",
    "platform": "",
    "sha256": "",
    "target_settings": [],
    "urls": [],
    "version": "",
}

# `apply_configure` expects every `uv.configure` attribute on an entry.
_MANIFEST_ENTRY_FIELDS = {
    "base_url": "",
    "manifest_filename": "",
}

# The fields that hold labels; they are passed on as strings.
_LABEL_LIST_FIELDS = ["compatible_with", "target_settings"]

def _normalize_entry(entry):
    """Validate a `configure` dict and return it as an entry struct."""
    if not types.is_dict(entry):
        fail("`configure` entries must be dicts, got {}: {}".format(
            type(entry),
            entry,
        ))
    unknown = [key for key in entry if key not in _ENTRY_FIELDS]
    if unknown:
        fail(
            "`configure` entry has unknown keys {}; ".format(unknown) +
            "expected a subset of {}: {}".format(sorted(_ENTRY_FIELDS), entry),
        )
    normalized = dict(_MANIFEST_ENTRY_FIELDS | _ENTRY_FIELDS)
    for key, value in entry.items():
        empty = _ENTRY_FIELDS[key]
        if types.is_dict(empty):
            ok = types.is_dict(value)
        elif types.is_list(empty):
            ok = types.is_list(value)
        else:
            ok = types.is_string(value)
        if not ok:
            fail("`configure` entry key `{}` expects a {}, got {}: {}".format(
                key,
                type(empty),
                type(value),
                entry,
            ))
        if key in _LABEL_LIST_FIELDS:
            value = [str(label) for label in value]
        normalized[key] = value
    return struct(**normalized)

def _uv_register_toolchains(
        *,
        name,
        manifests,
        version,
        configure,
        netrc,
        auth_patterns,
        uv_repository,
        hub_repo,
        register_toolchains):
    """The testable core of {obj}`uv_register_toolchains`.

    The repository rules and `register_toolchains` are injected.
    """
    manifests = manifests or {}
    version = version or (manifests.keys()[0] if manifests else DEFAULT_VERSION)

    # No entries behaves like one `uv.configure()` per fetched version, or
    # for the default version without manifests.
    if not configure:
        configure = [{"version": v} for v in manifests] or [{}]
    entries = [_normalize_entry(entry) for entry in configure]

    # The same role as the `uv.default()` tags under bzlmod.
    defaults = {
        "auth_patterns": auth_patterns or {},
        "base_url": "",
        "manifest_filename": "",
        "netrc": netrc or "",
        "platforms": DEFAULT_PLATFORMS,
        "version": version,
    }
    versions = apply_configure({}, entries, defaults = defaults, override = True)

    def _resolve_sources(*, version, **_kwargs):
        if version not in manifests:
            fail((
                "uv_register_toolchains(name = {name}): no release manifest " +
                "for uv {version}. Load `uv_register_toolchains` from the " +
                "`dist_manifest.bzl` of a `uv_toolchains_manifest` repository " +
                "that has {version} in its `versions`, or give `urls` for its " +
                "platforms in `configure`."
            ).format(name = repr(name), version = version))
        return {
            platform: struct(
                sha256 = source["sha256"],
                urls = source["urls"],
            )
            for platform, source in manifests[version].items()
        }

    define_toolchains(
        hub_name = name,
        versions = versions,
        uv_repository = uv_repository,
        hub_repo = hub_repo,
        toolchain_type = str(UV_TOOLCHAIN_TYPE),
        resolve_sources = _resolve_sources,
    )
    register_toolchains("@{}//:all".format(name))

def uv_register_toolchains(
        *,
        name = "uv",
        manifests = None,
        version = None,
        configure = None,
        netrc = None,
        auth_patterns = None):
    """Create the `uv` toolchain repositories and register them in a WORKSPACE file.

    This is the WORKSPACE equivalent of the {obj}`uv` module extension. It
    creates one download repository per `uv` version and platform, and the
    toolchain hub repository `name` with a `toolchain` for each of them, which
    it registers as `@{name}//:all`; {obj}`lock` can then be used. See the
    {ref}`WORKSPACE setup guide <uv-workspace-setup>` for usage examples.

    Platforms without an archive in a manifest get no toolchain. The
    `configure` entries are dicts with the attributes of {obj}`uv.configure`;
    refer to the {obj}`uv.configure` documentation for how entries are applied.

    :::{note}
    A Python toolchain must be registered as well, e.g. via
    {obj}`python_register_toolchains`, because {obj}`lock` uses the Python
    exec tools toolchain to run `uv` with a hermetic interpreter.
    :::

    :::{note}
    `compatible_with` and `target_settings` are written into the hub
    repository's `BUILD` file as-is, so plain strings resolve relative to
    `@{name}`; pass {type}`Label` objects or `@//`-qualified strings for
    targets in your own repository.
    :::

    :::{versionadded} VERSION_NEXT_FEATURE
    :::

    Args:
        name: {type}`str` the name of the toolchain hub repository. The
            download repositories are named `{name}_{version}_{platform}`
            with `.` and `-` replaced by `_`.
        manifests: {type}`dict[str, dict] | None` the download `urls` and
            `sha256` of the archives, keyed by version and then by platform
            (`{version: {platform: {"urls": [...], "sha256": "..."}}}`), as
            written to `dist_manifest.bzl` by {obj}`uv_toolchains_manifest`,
            which binds its own when `uv_register_toolchains` is loaded from
            there.
        version: {type}`str | None` the `uv` version for `configure` entries
            that do not name one. Defaults to the first version of
            `manifests`, or to the version the {obj}`uv` extension uses by
            default when there are none.
        configure: {type}`list[dict] | None` the entries to apply, each a
            dict with a subset of the {obj}`uv.configure` attributes:
            `version`, `platform`, `compatible_with`, `target_settings`,
            `urls`, `sha256`, `netrc` and `auth_patterns`. Defaults to one
            empty entry per version of `manifests`, i.e. every version with
            the default platforms, or to a single entry for `version`.
        netrc: {type}`str | None` the default location of the `.netrc` file
            to use for authenticating the archive downloads.
        auth_patterns: {type}`dict[str, str] | None` the default dict mapping
            host names to custom authorization patterns for the archive
            downloads, as understood by `http_archive`.
    """
    _uv_register_toolchains(
        name = name,
        manifests = manifests,
        version = version,
        configure = configure,
        netrc = netrc,
        auth_patterns = auth_patterns,
        uv_repository = uv_repository,
        hub_repo = uv_toolchains_repo,
        register_toolchains = native.register_toolchains,
    )

testing = struct(
    uv_register_toolchains = _uv_register_toolchains,
)
