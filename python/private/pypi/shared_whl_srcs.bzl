"""Share the extracted wheel repositories between the whl_library repositories.

A wheel is extracted once into a `whl_library` repository and each original
`whl_library` repository is replaced by a {obj}`whl_deps_repo` that wires the
dependencies of the wheel together by reading the `METADATA` from the extracted
repository.
"""

load("//python/private:normalize_name.bzl", "normalize_name")
load(":pep508_requirement.bzl", "requirement")
load(":urllib.bzl", "urllib")
load(":whl_archive.bzl", "whl_archive_attrs")
load(":whl_repo_name.bzl", "whl_repo_name")

# The args that are only used to wire the dependencies of the wheel and are
# passed to the `whl_deps_repo`.
_DEPS_ARGS = [
    # keep-sorted start
    "config_load",
    "dep_template",
    "group_deps",
    "group_name",
    "requirement",
    # keep-sorted end
]

# The args that only influence where the wheel is downloaded from. The first
# registration wins, because the wheel is identified by its URL, filename and
# integrity.
_DOWNLOAD_ARGS = [
    # keep-sorted start
    "auth_patterns",
    "envsubst",
    "index_url",
    "netrc",
    "urls",
    # keep-sorted end
]

# The args that modify the extracted wheel and that are not supported when
# sharing the extracted wheel.
_UNSUPPORTED_ARGS = [
    # keep-sorted start
    "annotation",
    "whl_patches",
    # keep-sorted end
]

def shared_whl_srcs(whl_libraries, *, hub_whl_map, extra_aliases):
    """Split the whl_library repositories into the extracted and deps repositories.

    The wheels that are downloaded with the Bazel downloader are extracted once
    for each unique URL, filename and integrity combination. The arguments that
    only control the download (e.g. `index_url` and `envsubst`) are taken
    from the first registration of the wheel.

    Args:
        whl_libraries: {type}`dict[str, dict[str, object]]` The `whl_library`
            repository names and the kwargs to create them with.
        hub_whl_map: {type}`dict[str, dict[str, dict[str, object]]]` The
            `whl_library` repository names for each package in each hub.
        extra_aliases: {type}`dict[str, dict[str, list[str]]]` The extra
            targets that each hub aliases for each package. These targets
            are not available in the `whl_deps_repo`, so the wheels of these
            packages are not shared.

    Returns:
        A struct with the following fields:
        * srcs: {type}`dict[str, dict[str, object]]` the `whl_library`
          repositories that only extract the wheel.
        * deps: {type}`dict[str, dict[str, object]]` the `whl_deps_repo`
          repositories that use the extracted wheel.
        * whl_libraries: {type}`dict[str, dict[str, object]]` the
          `whl_library` repositories that are created as before.
    """
    srcs = {}
    deps = {}
    libraries = {}
    srcs_name_by_key = {}
    exclude = _repos_with_extra_aliases(hub_whl_map, extra_aliases)

    for name, args in whl_libraries.items():
        if name in exclude or not _is_shareable(args):
            libraries[name] = args
            continue

        srcs_args = _srcs_args(args)
        key = _srcs_key(args)
        srcs_name = srcs_name_by_key.get(key)
        if srcs_name == None:
            srcs_name = _srcs_name(args["filename"], srcs, whl_libraries)
            srcs_name_by_key[key] = srcs_name
            srcs[srcs_name] = srcs_args
        elif _extract_args(srcs[srcs_name]) != _extract_args(srcs_args):
            # The wheel is extracted differently, e.g. the `pip_data_exclude`
            # is different between the hubs.
            libraries[name] = args
            continue

        deps[name] = _deps_args(args, srcs_name)

    return struct(
        srcs = srcs,
        deps = deps,
        whl_libraries = libraries,
    )

def _repos_with_extra_aliases(hub_whl_map, extra_aliases):
    """Return the `whl_library` repos that have extra targets aliased by a hub."""
    repos = {}
    for hub_name, whl_map in hub_whl_map.items():
        hub_extra_aliases = extra_aliases.get(hub_name, {})
        for whl_name, whl_repos in whl_map.items():
            if not hub_extra_aliases.get(normalize_name(whl_name)):
                continue
            for repo in whl_repos:
                repos[repo] = None
    return repos

def _is_shareable(args):
    """Return True if the wheel is downloaded with the Bazel downloader."""
    for arg in _UNSUPPORTED_ARGS:
        if arg in args:
            return False

    filename = args.get("filename", "")

    # The integrity is empty if the digest cannot be represented as SRI, then
    # we cannot ensure that the URLs point to the same file.
    return bool(args.get("urls")) and filename.endswith(".whl") and bool(args.get("integrity"))

def _srcs_key(args):
    """Return the key identifying the downloaded wheel.

    The URLs are not resolved using `envsubst`, so that credentials do not end
    up in the key.
    """
    index_url = args.get("index_url", "")
    urls = tuple([
        urllib.absolute_url(index_url, url)
        for url in args["urls"]
    ])
    return (urls, args["filename"], args["integrity"])

def _srcs_args(args):
    """Return the args for the `whl_library` that only extracts the wheel."""
    srcs_args = {
        k: v
        for k, v in args.items()
        if k in whl_archive_attrs and k not in _DEPS_ARGS
    }

    # The extras do not influence the extraction of the wheel, but the
    # requirement is mandatory.
    srcs_args["requirement"] = requirement(args["requirement"]).name

    # Do not create the dependency targets in the extracted repo.
    srcs_args["dep_template"] = ""
    return srcs_args

def _extract_args(srcs_args):
    """Return the args that influence how the wheel is extracted."""
    return {
        k: v
        for k, v in srcs_args.items()
        if k not in _DOWNLOAD_ARGS
    }

def _deps_args(args, srcs_name):
    """Return the args for the `whl_deps_repo`."""
    deps_args = {
        k: v
        for k, v in args.items()
        if k in _DEPS_ARGS
    }
    deps_args["metadata_file"] = "@{}//:metadata.json".format(srcs_name)
    return deps_args

def _srcs_name(filename, srcs, whl_libraries):
    """Return a unique repository name for the extracted wheel.

    Wheels with the same filename but different URLs or integrity get a numeric
    suffix in the order they are registered.
    """
    base = "whl_" + whl_repo_name(filename, "")
    name = base
    for i in range(2, len(srcs) + len(whl_libraries) + 3):
        if name not in srcs and name not in whl_libraries:
            break
        name = "{}_{}".format(base, i)
    return name
