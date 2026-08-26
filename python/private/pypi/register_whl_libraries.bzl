"TODO"

load(":whl_archive.bzl", "whl_archive")
load(":whl_deps_repo.bzl", "whl_deps_repo")
load(":whl_library.bzl", "whl_library")
load(":whl_repo_name.bzl", "whl_repo_name")

def register_whl_libraries(
        registrations,
        rules = struct(
            whl_library = whl_library,
            whl_deps_repo = whl_deps_repo,
            whl_archive = whl_archive,
        )):
    """Register all of the whl libraries that where produced by the extension.

    Args:
        registrations: {type}`dict[str, dict[str, Any]]` The args to pass to
            the repository rules when processing everything.
        rules: {type}`struct` used to inject different implementations used to
            create instances. Used for testing.
    """

    # we first check which wheels are ambiguous - belong to the same hub repository, indicated
    # by the `dep_template`, but have different (URL, index_url) pairs for each whl.
    urls = {}
    fallback = {}
    separate_srcs = {}
    for name, args in registrations.items():
        if not _can_split(args):
            continue

        # For each each integrity, filename, we should have a unique url and index_url
        # used across all of the hub repos, if not, print a warning and fallback to the
        # previous behaviour of not using the source repository.
        #
        # If the filename is the same but it has a different sha256, then it means that
        # there could be one of the following situations:
        # 1. dependency confusion.
        # 2. somebody patched the wheel.
        # 3. it is an unlucky coincidence.
        #
        # Any of these cases are a bit tricky to get right, the repo name is derived
        # filename together. The repo name is derived from the filename and a hash for
        # this reason.
        integrity = args["integrity"]
        filename = args["filename"]

        url = args["urls"][0]
        index_url = args["index_url"]

        # TODO @aignas 2026-08-24: have different levels, register at hub level, register
        # globally and fallback. This can be done by storing different keys.
        hub_name, _, _ = args["dep_template"].partition("//")
        hub_name = hub_name.strip("@")

        # for now we include the hub_name in the key since the reuse is done for each
        # hub_name separately.
        key = (None, filename, integrity)
        hkey = (hub_name, filename, integrity)
        value = (url, index_url)

        if key in fallback:
            continue

        got = urls.setdefault(key, value)
        if got != value and got != None:
            urls.pop(key)
            urls.setdefault(key, None)
            got = None

        got2 = urls.setdefault(hkey, value)
        if got2 != value and got2 != None:
            urls.pop(hkey)
            urls.setdefault(hkey, None)
            got2 = None

        if got != None:
            separate_srcs[name] = key
        elif got2 != None:
            separate_srcs[name] = hkey

    for name, args in registrations.items():
        if name in separate_srcs:
            # first handle the regular case
            continue

        rules.whl_library(name = name, **args)

    # Then handle the reusable case
    registered_srcs = {}
    for name, key in separate_srcs.items():
        args = registrations[name]
        hub_name, _, integrity = key

        filename = args["filename"]
        extract_args = {
            k: v
            for k, v in args.items()
            if k not in {
                "config_load": None,
                "dep_template": None,
            }
        }

        # The extras do not affect the extraction, so normalize the requirement
        # to allow the same wheel to be extracted only once.
        extract_args["requirement"] = _without_extras(extract_args["requirement"])
        extract_repo_name = whl_repo_name(filename, "")
        if hub_name:
            extract_repo_name = "{}_{}".format(hub_name, extract_repo_name)

        if key not in registered_srcs:
            registered_srcs[key] = extract_repo_name
            rules.whl_archive(
                name = extract_repo_name,
                **extract_args
            )

        deps_args = {
            k: args.get(k)
            for k in [
                "config_load",
                "requirement",
                "dep_template",
                "group_deps",
                "group_name",
                "repo_prefix",
            ]
            if args.get(k) != None
        } | {
            "metadata_file": "@{}//:metadata.json".format(extract_repo_name),
        }
        rules.whl_deps_repo(
            name = name,
            **deps_args
        )

def _can_split(
        args,
        need_args = [
            "dep_template",
            "urls",
            "filename",
            "integrity",
        ],
        cannot_split = ["annotation", "whl_patches"]):
    for arg in need_args:
        if arg not in args:
            # missing args for splitting logic
            return False

    for arg in cannot_split:
        if arg in args:
            # cannot split if any of these exist
            return False

    return True

def _without_extras(requirement_line):
    """Remove the extras from a requirement line.

    The extras do not affect which wheel is downloaded and extracted, so they
    can be removed to allow the same wheel to be extracted only once even when
    it is referenced with different extras.

    Args:
        requirement_line: {type}`str` the requirement line, e.g.
            `foo[bar]==1.0 --hash=sha256:...`.

    Returns:
        The requirement line without the extras, e.g. `foo==1.0 --hash=sha256:...`.
    """
    name_and_version, _, extras = requirement_line.partition("[")
    if not extras:
        return requirement_line
    _, _, rest = extras.partition("]")
    return name_and_version + rest
