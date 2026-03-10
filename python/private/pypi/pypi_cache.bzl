"""A cache for the PyPI index contents evaluation.

This is design to work as the following:
- in-memory cache for results of PyPI index queries, so that we are not calling PyPI multiple times
  for the same package for different hub repos.

In the future the same will be used to:
- Store PyPI index query results as facts in the MODULE.bazel.lock file
"""

load(":version_from_filename.bzl", "version_from_filename")

_FACT_VERSION = "v1"

def pypi_cache(module_ctx = None, store = None):
    """The cache for PyPI index queries.

    Currently the key is of the following structure:
    (url, real_url, versions)

    Args:
        module_ctx: The module context
        store: The in-memory store, should implement dict interface for get and setdefault

    Returns:
        A cache struct
    """
    mcache = memory_cache(store)
    facts = {}
    fcache = facts_cache(getattr(module_ctx, "facts", None), facts)

    # buildifier: disable=uninitialized
    self = struct(
        _mcache = mcache,
        _facts = fcache,
        setdefault = lambda key, parsed_result: _pypi_cache_setdefault(self, key, parsed_result),
        get = lambda key: _pypi_cache_get(self, key),
        get_facts = lambda: _get_facts(facts),
    )

    # buildifier: enable=uninitialized
    return self

def _pypi_cache_setdefault(self, key, parsed_result):
    """Store the value if not yet cached.

    Args:
        self: {type}`struct` The self of this implementation.
        key: {type}`str` The cache key, can be any string.
        parsed_result: {type}`struct` The result of `parse_simpleapi_html` function.

    index_url and distribution is used to write to the MODULE.bazel.lock file as facts
    real_index_url and distribution is used to write to in-memory cache to ensure that there are
    no duplicate calls to the PyPI indexes

    Returns:
        The `parse_result`.
    """
    index_url, real_url, versions = key
    self._mcache.setdefault(real_url, None, parsed_result)
    if not versions or not self._facts:
        return parsed_result

    filtered = _filter_packages(parsed_result, versions)
    return self._facts.setdefault(index_url, filtered)

def _pypi_cache_get(self, key):
    """Return the parsed result from the cache.

    Args:
        self: {type}`struct` The self of this implementation.
        key: {type}`str` The cache key, can be any string.

    Returns:
        The {type}`struct` or `None` based on if the result is in the cache or not.
    """
    index_url, real_url, versions = key
    cached = self._mcache.get(real_url, versions)
    if not self._facts:
        return cached

    if not cached and versions:
        # Could not get from in-memory, read from lockfile facts
        cached = self._facts.get(index_url, versions)

    return cached

def _get_facts(facts):
    return facts

def memory_cache(cache = None):
    """SimpleAPI cache for making fewer calls.

    Args:
        cache: the storage to store things in memory.

    Returns:
        struct with 2 methods, `get` and `setdefault`.
    """
    if cache == None:
        cache = {}

    return struct(
        get = lambda real_url, versions: _filter_packages(cache.get(real_url), versions),
        setdefault = lambda real_url, versions, value: _filter_packages(cache.get(real_url), versions),
    )

def _filter_packages(dists, requested_versions):
    if dists == None:
        return None

    if not requested_versions:
        return dists

    sha256s_by_version = {}
    whls = {}
    sdists = {}

    for sha256, d in dists.sdists.items():
        if d.version not in requested_versions:
            continue

        sdists[sha256] = d
        sha256s_by_version.setdefault(d.version, []).append(sha256)

    for sha256, d in dists.whls.items():
        if d.version not in requested_versions:
            continue

        whls[sha256] = d
        sha256s_by_version.setdefault(d.version, []).append(sha256)

    if not whls and not sdists:
        # TODO @aignas 2026-03-08: add logging
        #print("WARN: no dists matched for versions {}".format(requested_versions))
        return None

    return struct(
        whls = whls,
        sdists = sdists,
        sha256s_by_version = sha256s_by_version,
    )

def facts_cache(known_facts, facts, facts_version = _FACT_VERSION):
    if known_facts == None:
        return None

    return struct(
        get = lambda index_url, versions: _get_from_facts(
            facts,
            known_facts,
            index_url,
            versions,
            facts_version,
        ),
        setdefault = lambda url, value: _store_facts(facts, facts_version, url, value),
        known_facts = known_facts,
        facts = facts,
    )

def _get_from_facts(facts, known_facts, index_url, requested_versions, facts_version):
    if known_facts.get("fact_version") != facts_version:
        # cannot trust known facts, different version that we know how to parse
        return None

    known_sources = {}

    root_url, _, distribution = index_url.rstrip("/").rpartition("/")
    distribution = distribution.rstrip("/")
    root_url = root_url.rstrip("/")

    for url, sha256 in known_facts.get("dist_hashes", {}).get(root_url, {}).get(distribution, {}).items():
        filename = known_facts.get("dist_filenames", {}).get(root_url, {}).get(distribution, {}).get(sha256)
        if not filename:
            _, _, filename = url.rpartition("/")

        version = version_from_filename(filename)
        if version not in requested_versions:
            # TODO @aignas 2026-01-21: do the check by requested shas at some point
            # We don't have sufficient info in the lock file, need to call the API
            #
            continue

        if filename.endswith(".whl"):
            dists = known_sources.setdefault("whls", {})
        else:
            dists = known_sources.setdefault("sdists", {})

        known_sources.setdefault("sha256s_by_version", {}).setdefault(version, []).append(sha256)

        dists.setdefault(sha256, struct(
            sha256 = sha256,
            filename = filename,
            version = version,
            url = url,
            yanked = known_facts.get("dist_yanked", {}).get(root_url, {}).get(distribution, {}).get(sha256, ""),
        ))

    if not known_sources:
        # We found nothing in facts
        return None

    output = struct(
        whls = known_sources.get("whls", {}),
        sdists = known_sources.get("sdists", {}),
        sha256s_by_version = known_sources.get("sha256s_by_version", {}),
    )

    # Persist these facts for the next run because we have used them.
    return _store_facts(facts, facts_version, index_url, output)

def _store_facts(facts, fact_version, index_url, value):
    """Store values as facts in the lock file.

    The main idea is to ensure that the lock file is small and it is only storing what
    we would need to fetch from the internet. Any derivative information we can
    from this that can be achieved using pure Starlark functions should be done in
    Starlark.
    """
    if not value:
        return value

    facts["fact_version"] = fact_version

    root_url, _, distribution = index_url.rstrip("/").rpartition("/")
    distribution = distribution.rstrip("/")
    root_url = root_url.rstrip("/")

    for sha256, d in (value.sdists | value.whls).items():
        facts.setdefault("dist_hashes", {}).setdefault(root_url, {}).setdefault(distribution, {}).setdefault(d.url, sha256)
        if not d.url.endswith(d.filename):
            facts.setdefault("dist_filenames", {}).setdefault(root_url, {}).setdefault(distribution, {}).setdefault(d.url, d.filename)
        if d.yanked:
            facts.setdefault("dist_yanked", {}).setdefault(root_url, {}).setdefault(distribution, {}).setdefault(sha256, d.yanked)

    return value
