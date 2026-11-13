"""A cache for the PyPI index contents evaluation.

This is designed to work as the following:
- in-memory cache for results of PyPI index queries, so that we are not calling PyPI multiple times
  for the same package for different hub repos.

In the future the same will be used to:
- Store PyPI index query results as facts in the MODULE.bazel.lock file
"""

load(":version_from_filename.bzl", "version_from_filename")

# This value should be changed whenever the storage format changes.
# Changing it simply means the information cached in the lockfile has to be
# recomputed.
#
# v2: the `dist_hashes` values and the `dist_yanked` keys are canonical
#      `<algo>:<digest>` strings instead of bare sha256 hex digests.
# v3: facts are shallow and compact. Index URL facts are keyed by
#      `<pkg_normalized>@<index_url>` and distribution facts are keyed by
#      `<distribution>@<root_url>`. Each distribution URL maps to a single
#      string with only the information that cannot be derived from the URL:
#      `<digest>[|<filename>[|<yanked>]]`.
_FACT_VERSION = "v3"

def pypi_cache(mctx = None, store = None):
    """The cache for PyPI index queries.

    Currently the key is of the following structure:
    (url, real_url, versions)

    Args:
        mctx: The module context
        store: The in-memory store, should implement dict interface for get and setdefault

    Returns:
        A cache struct
    """
    mcache = memory_cache(store)
    fcache = facts_cache(getattr(mctx, "facts", None))

    # buildifier: disable=uninitialized
    self = struct(
        _mcache = mcache,
        _facts = fcache,
        setdefault = lambda key, parsed_result: _pypi_cache_setdefault(self, key, parsed_result),
        get = lambda key: _pypi_cache_get(self, key),
        get_facts = lambda: _pypi_cache_get_facts(self),
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
    self._mcache.setdefault(real_url, parsed_result)
    if not versions or not self._facts:
        return parsed_result

    # Filter the packages to only what is needed before writing to the facts cache
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

    # When retrieving from memory cache, filter down to only what is needed. If the
    # cache is empty, we will attempt to read from facts, however, reading from memory
    # first allows us to not parse the contents of the lock file that may add up.
    cached = _filter_packages(self._mcache.get(real_url), versions)
    if not self._facts:
        return cached

    if not cached and versions:
        # Could not get from in-memory, read from lockfile facts
        cached = self._facts.get(index_url, versions)
    else:
        # We might be using something from memory that is not yet stored in facts (e.g. we processed
        # the requirements.txt for one Python version and the deps got cached, but new python
        # version means different deps, which may add extras.
        self._facts.setdefault(index_url, cached)

    return cached

def _pypi_cache_get_facts(self):
    if not self._facts:
        return {}

    return self._facts.facts

def memory_cache(cache = None):
    """SimpleAPI cache for making fewer calls.

    We are using the `real_url` as the key in the cache functions on purpose in order to get the
    best possible cache hits.

    Args:
        cache: the storage to store things in memory.

    Returns:
        struct with 2 methods, `get` and `setdefault`.
    """
    if cache == None:
        cache = {}

    return struct(
        get = lambda real_url: cache.get(real_url),
        setdefault = lambda real_url, value: cache.setdefault(real_url, value),
    )

def _filter_packages(dists, requested_versions):
    if dists == None or not requested_versions:
        return dists

    if type(dists) == "dict":
        result = {
            pkg: url
            for pkg, url in dists.items()
            if pkg in requested_versions
        }
        return result if result else None

    hashes_by_version = {}
    whls = {}
    sdists = {}

    for digest, d in dists.sdists.items():
        if d.version not in requested_versions:
            continue

        sdists[digest] = d
        hashes_by_version.setdefault(d.version, []).append(digest)

    for digest, d in dists.whls.items():
        if d.version not in requested_versions:
            continue

        whls[digest] = d
        hashes_by_version.setdefault(d.version, []).append(digest)

    if not whls and not sdists:
        # TODO @aignas 2026-03-08: add logging
        #print("WARN: no dists matched for versions {}".format(requested_versions))
        return None

    return struct(
        whls = whls,
        sdists = sdists,
        hashes_by_version = {
            k: sorted(v)
            for k, v in hashes_by_version.items()
        },
    )

def facts_cache(known_facts, facts_version = _FACT_VERSION):
    """The facts cache.

    Here we have a way to store things as facts and the main thing to keep in mind is that we should
    not use the real_url in case it contains credentials in it (e.g. is of form `https://<username>:<password>@<host>`).

    Args:
        known_facts: An opaque object coming from {obj}`module_ctx.facts`.
        facts_version: {type}`str` the version of the facts schema, used for short-circuiting.

    Returns:
        A struct that has:
            * `get` method for getting values from the facts cache.
            * `setdefault` method for setting values in the cache.
            * `facts` attribute that should be passed to the {obj}`module_ctx.extension_metadata` to persist facts.
    """
    if known_facts == None:
        return None

    facts = {}

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

    if type(requested_versions) == "dict":
        result = {}
        for pkg in requested_versions.keys():
            url = known_facts.get(_index_fact_key(pkg, index_url))
            if url == None:
                # If the results are incomplete, return None, so that we can
                # fetch sources from the internet again.
                return None
            result[pkg] = url

        # Only persist the accessed (requested) packages. Packages that
        # exist in known_facts but are not in requested_versions (e.g.
        # removed from all requirements files) are dropped from the
        # computed facts so they get cleaned up from the lockfile.
        return _store_facts(facts, facts_version, index_url, result)

    fact_key = _dist_fact_key(index_url)
    known_sources = {}
    retrieved_versions = {}
    used_entries = {}

    for url, entry in known_facts.get(fact_key, {}).items():
        if type(entry) != "string":
            # Defensive: `fact_version` guards against older schemas, but the
            # facts come from a user-editable lockfile (e.g. a botched merge),
            # so skip anything that is not an encoded entry instead of failing.
            continue

        filename, digest, yanked = _decode_dist_entry(entry, url)

        version = version_from_filename(filename)
        if version not in requested_versions:
            continue

        retrieved_versions[version] = True
        used_entries[url] = entry

        if filename.endswith(".whl"):
            dists = known_sources.setdefault("whls", {})
        else:
            dists = known_sources.setdefault("sdists", {})

        # NOTE: an empty digest is kept so that the result matches the
        # output of `parse_simpleapi_html` for indexes that do not advertise
        # any hashes.
        known_sources.setdefault("hashes_by_version", {}).setdefault(version, []).append(digest)

        dists.setdefault(digest, struct(
            digest = digest,
            filename = filename,
            version = version,
            metadata_url = "",
            metadata_sha256 = "",
            url = url,
            yanked = yanked,
        ))

    if not known_sources:
        # We found nothing in facts
        return None

    if len(requested_versions) != len(retrieved_versions):
        # If the results are incomplete, then return None, so that we can fetch sources from the
        # internet again.
        return None

    # Persist these facts for the next run because we have used them. The raw
    # entries are copied as-is instead of re-encoding the decoded structs, so
    # that a no-op run leaves the lockfile unchanged.
    facts["fact_version"] = facts_version
    facts.setdefault(fact_key, {}).update(used_entries)

    return struct(
        whls = known_sources.get("whls", {}),
        sdists = known_sources.get("sdists", {}),
        hashes_by_version = {
            k: sorted(v)
            for k, v in known_sources.get("hashes_by_version", {}).items()
        },
    )

def _store_facts(facts, fact_version, index_url, value):
    """Store values as facts in the lock file.

    The main idea is to ensure that the lock file is small and it is only
    storing what we would need to fetch from the internet. Any derivative
    information we can get from this that can be achieved using pure Starlark
    functions should be done in Starlark.

    All keys are top-level so that Bazel's lockfile merge driver can merge
    concurrent changes to different packages cleanly. The schema is:

    ```
    facts: {
      "fact_version": "<_FACT_VERSION>",

      # From the index page, e.g. `foo@https://pypi.org/simple/`
      "<pkg_normalized>@<index_url>": "<package page URL>",

      # From the package page, e.g. `foo@https://pypi.org/simple`
      "<distribution>@<root_url>": {
        "<dist url>": "<encoded entry>",  # see `_encode_dist_entry`
      },
    }
    ```

    Adding a new field to the encoded entry requires bumping `_FACT_VERSION`.
    """
    if not value:
        return value

    facts["fact_version"] = fact_version

    if type(value) == "dict":
        for pkg, url in value.items():
            facts[_index_fact_key(pkg, index_url)] = url
        return value

    fact_key = _dist_fact_key(index_url)
    entries = facts.setdefault(fact_key, {})

    # NOTE: iterate separately instead of `sdists | whls`, because both are
    # keyed by digest and hashless sdists and wheels would collide on `""`.
    for dists in (value.sdists, value.whls):
        for digest, d in dists.items():
            entries[d.url] = _encode_dist_entry(digest, d)

    return value

def _index_fact_key(pkg, index_url):
    """Return the fact key for a package found on an index page.

    The key is `<pkg_normalized>@<index_url>`, so that the lockfile entries
    are grouped by the package name.

    The `index_url` always ends with `/` (see `simpleapi_download`), whereas
    the `root_url` in {obj}`_dist_fact_key` never does. This is what keeps
    the two kinds of keys from colliding for the same package and index.

    Args:
        pkg: {type}`str` The normalized package name.
        index_url: {type}`str` The URL of the index page, e.g.
            `https://pypi.org/simple/`.

    Returns:
        {type}`str` The fact key, e.g. `foo@https://pypi.org/simple/`.
    """
    return pkg + "@" + index_url

def _dist_fact_key(index_url):
    """Return the fact key for the distributions of a package index page.

    The key is `<distribution>@<root_url>`, so that the lockfile entries are
    grouped by the package name. The `root_url` never ends with `/`, which
    keeps it distinct from the {obj}`_index_fact_key` for the same package.

    Args:
        index_url: {type}`str` The URL of the package page in the index, e.g.
            `https://pypi.org/simple/foo/`.

    Returns:
        {type}`str` The fact key, e.g. `foo@https://pypi.org/simple`.
    """
    root_url, _, distribution = index_url.rstrip("/").rpartition("/")
    return distribution + "@" + root_url.rstrip("/")

def _encode_dist_entry(digest, dist):
    """Encode a distribution into a compact string.

    The format is `<digest>[|<filename>[|<yanked>]]`. Only the digest is
    stored if the filename can be derived from the URL and the distribution
    is not yanked, which is the common case. Otherwise the optional fields are
    appended in a fixed order so that reading the value back is unambiguous:

    * `<digest>` - the filename is the URL basename and it is not yanked.
    * `<digest>|<filename>` - the filename differs from the URL basename.
    * `<digest>||<yanked>` - the filename is the URL basename and it is yanked.
    * `<digest>|<filename>|<yanked>` - both differ.

    The yank reason is the last field, so it may itself contain `|`. An empty
    yank reason is still distinct from not being yanked.

    Args:
        digest: {type}`str` The canonical `<algo>:<digest>` value.
        dist: {type}`struct` The distribution struct to encode.

    Returns:
        {type}`str` The compact representation of the distribution.
    """
    _, _, default_filename = dist.url.rpartition("/")
    has_diff = dist.filename != default_filename
    is_yanked = dist.yanked != None

    if is_yanked:
        return "|".join([digest, dist.filename if has_diff else "", dist.yanked])
    elif has_diff:
        return digest + "|" + dist.filename
    else:
        return digest

def _decode_dist_entry(entry, url):
    """Decode a distribution from its compact string representation.

    Args:
        entry: {type}`str` The compact representation created by
            `_encode_dist_entry`.
        url: {type}`str` The distribution URL, used to derive the default
            filename.

    Returns:
        A tuple of `(filename, digest, yanked)`.
    """
    parts = entry.split("|", 2)
    digest = parts[0]
    filename = parts[1] if len(parts) > 1 else ""
    yanked = parts[2] if len(parts) > 2 else None

    if not filename:
        _, _, filename = url.rpartition("/")

    return filename, digest, yanked
