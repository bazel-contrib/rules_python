# Copyright 2024 The Bazel Authors. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

"""
A file that houses private functions used in the `bzlmod` extension with the same name.
"""

load("@bazel_features//:features.bzl", "bazel_features")
load("//python/private:auth.bzl", _get_auth = "get_auth")
load("//python/private:envsubst.bzl", "envsubst")
load("//python/private:normalize_name.bzl", "normalize_name")
load("//python/private:text_util.bzl", "render")
load(":parse_simpleapi_html.bzl", "absolute_url", "parse_simpleapi_html", "pkg_version")

_FACT_VERSION = "v1"

def simpleapi_download(
        ctx,
        *,
        attr,
        cache,
        parallel_download = True,
        read_simpleapi = None,
        get_auth = None,
        _fail = fail):
    """Download Simple API HTML.

    Args:
        ctx: The module_ctx or repository_ctx.
        attr: Contains the parameters for the download. They are grouped into a
          struct for better clarity. It must have attributes:
           * index_url: str, the index.
           * index_url_overrides: dict[str, str], the index overrides for
             separate packages.
           * extra_index_urls: Extra index URLs that will be looked up after
             the main is looked up.
           * sources: list[str] | dict[str, list[str]], the sources to download things for. Each
               value is the contents of requirements files.
           * envsubst: list[str], the envsubst vars for performing substitution in index url.
           * netrc: The netrc parameter for ctx.download, see http_file for docs.
           * auth_patterns: The auth_patterns parameter for ctx.download, see
               http_file for docs.
           * facts: The facts to write to if we support them.
        cache: A dictionary that can be used as a cache between calls during a
            single evaluation of the extension. We use a dictionary as a cache
            so that we can reuse calls to the simple API when evaluating the
            extension. Using the canonical_id parameter of the module_ctx would
            deposit the simple API responses to the bazel cache and that is
            undesirable because additions to the PyPI index would not be
            reflected when re-evaluating the extension unless we do
            `bazel clean --expunge`.
        parallel_download: A boolean to enable usage of bazel 7.1 non-blocking downloads.
        read_simpleapi: a function for reading and parsing of the SimpleAPI contents.
            Used in tests.
        get_auth: A function to get auth information passed to read_simpleapi. Used in tests.
        _fail: a function to print a failure. Used in tests.

    Returns:
        dict of pkg name to the parsed HTML contents - a list of structs.
    """
    index_url_overrides = {
        normalize_name(p): i
        for p, i in (attr.index_url_overrides or {}).items()
    }

    download_kwargs = {}
    if bazel_features.external_deps.download_has_block_param:
        download_kwargs["block"] = not parallel_download

    # NOTE @aignas 2024-03-31: we are not merging results from multiple indexes
    # to replicate how `pip` would handle this case.
    contents = {}
    index_urls = [attr.index_url] + attr.extra_index_urls
    read_simpleapi = read_simpleapi or _read_simpleapi

    if attr.facts:
        ctx.report_progress("Fetch package lists from PyPI index or read from MODULE.bazel.lock")
    else:
        ctx.report_progress("Fetch package lists from PyPI index")

    cache = simpleapi_cache(
        memory_cache = memory_cache(cache),
        facts_cache = facts_cache(getattr(ctx, "facts", None), attr.facts),
    )

    found_on_index = {}
    warn_overrides = False

    # Normalize the inputs
    if type(attr.sources) == "list":
        fail("TODO")
    else:
        input_sources = attr.sources

    for i, index_url in enumerate(index_urls):
        if i != 0:
            # Warn the user about a potential fix for the overrides
            warn_overrides = True

        async_downloads = {}
        sources = {pkg: versions for pkg, versions in input_sources.items() if pkg not in found_on_index}
        for pkg, versions in sources.items():
            pkg_normalized = normalize_name(pkg)
            result = read_simpleapi(
                ctx = ctx,
                attr = attr,
                cache = cache,
                index_url = index_url_overrides.get(pkg_normalized, index_url),
                distribution = pkg,
                get_auth = get_auth,
                requested_versions = {v: None for v in versions},
                **download_kwargs
            )
            if hasattr(result, "wait"):
                # We will process it in a separate loop:
                async_downloads[pkg] = struct(
                    pkg_normalized = pkg_normalized,
                    wait = result.wait,
                    fns = result.fns,
                )
            elif result.success:
                contents[pkg_normalized] = result.output
                found_on_index[pkg] = index_url

        if not async_downloads:
            continue

        # If we use `block` == False, then we need to have a second loop that is
        # collecting all of the results as they were being downloaded in parallel.
        for pkg, download in async_downloads.items():
            result = download.wait()

            if result.success:
                contents[download.pkg_normalized] = result.output
                found_on_index[pkg] = index_url

    failed_sources = [pkg for pkg in attr.sources if pkg not in found_on_index]
    if failed_sources:
        pkg_index_urls = {
            pkg: index_url_overrides.get(
                normalize_name(pkg),
                index_urls,
            )
            for pkg in failed_sources
        }

        _fail(
            """
Failed to download metadata of the following packages from urls:
{pkg_index_urls}

If you would like to skip downloading metadata for these packages please add 'simpleapi_skip={failed_sources}' to your 'pip.parse' call.
""".format(
                pkg_index_urls = render.dict(pkg_index_urls),
                failed_sources = render.list(failed_sources),
            ),
        )
        return None

    if warn_overrides:
        index_url_overrides = {
            pkg: found_on_index[pkg]
            for pkg in attr.sources
            if found_on_index[pkg] != attr.index_url
        }

        if index_url_overrides:
            # buildifier: disable=print
            print("You can use the following `index_url_overrides` to avoid the 404 warnings:\n{}".format(
                render.dict(index_url_overrides),
            ))

    return contents

def _download_simpleapi(*, ctx, url, real_url, attr_envsubst, get_auth, **kwargs):
    output_str = envsubst(
        url,
        attr_envsubst,
        # Use env names in the subst values - this will be unique over
        # the lifetime of the execution of this function and we also use
        # `~` as the separator to ensure that we don't get clashes.
        {e: "~{}~".format(e) for e in attr_envsubst}.get,
    )

    # Transform the URL into a valid filename
    for char in [".", ":", "/", "\\", "-"]:
        output_str = output_str.replace(char, "_")

    output = ctx.path(output_str.strip("_").lower() + ".html")

    get_auth = get_auth or _get_auth

    # NOTE: this may have block = True or block = False in the kwargs
    download = ctx.download(
        url = [real_url],
        output = output,
        auth = get_auth(ctx, [real_url], ctx_attr = attr),
        allow_fail = True,
        **kwargs
    )

    return _await(
        download,
        _read,
        ctx = ctx,
        output = output,
    )

def _await(download, fn, **kwargs):
    if hasattr(download, "fns"):
        download.fns.append(
            lambda result: fn(result = result, **kwargs),
        )
        return download
    elif hasattr(download, "wait"):
        # Have a reference type which we can iterate later when aggregating the result
        fns = [lambda result: fn(result = result, **kwargs)]

        def wait():
            result = download.wait()
            for fn in fns:
                result = fn(result = result)
            return result

        return struct(
            wait = wait,
            fns = fns,
        )

    return fn(result = download, **kwargs)

def _read(ctx, result, output):
    if not result.success:
        return result

    return struct(success = True, output = ctx.read(output))

def strip_empty_path_segments(url):
    """Removes empty path segments from a URL. Does nothing for urls with no scheme.

    Public only for testing.

    Args:
        url: The url to remove empty path segments from

    Returns:
        The url with empty path segments removed and any trailing slash preserved.
        If the url had no scheme it is returned unchanged.
    """
    scheme, _, rest = url.partition("://")
    if rest == "":
        return url
    stripped = "/".join([p for p in rest.split("/") if p])
    if url.endswith("/"):
        return "{}://{}/".format(scheme, stripped)
    else:
        return "{}://{}".format(scheme, stripped)

def _read_simpleapi(ctx, index_url, distribution, attr, cache, requested_versions, get_auth = None, **download_kwargs):
    """Read SimpleAPI.

    Args:
        ctx: The module_ctx or repository_ctx.
        index_url: str, the PyPI SimpleAPI index URL
        distribution: str, the distribution to download
        attr: The attribute that contains necessary info for downloading. The
          following attributes must be present:
           * envsubst: The envsubst values for performing substitutions in the URL.
           * netrc: The netrc parameter for ctx.download, see http_file for docs.
           * auth_patterns: The auth_patterns parameter for ctx.download, see
               http_file for docs.
        cache: A dict for storing the results.
        get_auth: A function to get auth information. Used in tests.
        requested_versions: the list of requested versions.
        **download_kwargs: Any extra params to ctx.download.
            Note that output and auth will be passed for you.

    Returns:
        A similar object to what `download` would return except that in result.out
        will be the parsed simple api contents.
    """

    index_url = index_url.rstrip("/")

    # NOTE @aignas 2024-03-31: some of the simple APIs use relative URLs for
    # the whl location and we cannot handle multiple URLs at once by passing
    # them to ctx.download if we want to correctly handle the relative URLs.
    # TODO: Add a test that env subbed index urls do not leak into the lock file.

    cached = cache.get(index_url, distribution, requested_versions)
    if cached:
        return struct(success = True, output = cached)

    url = "{}/{}/".format(index_url, distribution)
    real_url = strip_empty_path_segments(envsubst(
        url,
        attr.envsubst,
        ctx.getenv if hasattr(ctx, "getenv") else ctx.os.environ.get,
    ))

    download = _download_simpleapi(
        ctx = ctx,
        url = url,
        real_url = real_url,
        attr_envsubst = attr.envsubst,
        get_auth = get_auth,
        **download_kwargs
    )

    return _await(
        download,
        _read_index_result,
        index_url = index_url,
        distribution = distribution,
        real_url = real_url,
        cache = cache,
        requested_versions = requested_versions,
    )

def _read_index_result(*, result, index_url, distribution, real_url, cache, requested_versions):
    if not result.success or not result.output:
        return struct(success = False)

    # TODO @aignas 2026-02-08: make this the only behaviour, maybe can get rid of `real_url
    output = parse_simpleapi_html(
        url = real_url,
        content = result.output,
        return_absolute = False,
    )
    if not output:
        return struct(success = False)

    cache.setdefault(index_url, distribution, requested_versions, output)
    return struct(success = True, output = output)

def simpleapi_cache(memory_cache, facts_cache):
    """SimpleAPI cache for making fewer calls.

    Args:
        memory_cache: the storage to store things in memory.
        facts_cache: the storage to retrieve known facts.

    Returns:
        struct with 2 methods, `get` and `setdefault`.
    """
    return struct(
        get = lambda index_url, distribution, versions: _cache_get(
            memory_cache,
            facts_cache,
            index_url,
            distribution,
            versions,
        ),
        setdefault = lambda index_url, distribution, versions, value: _cache_setdefault(
            memory_cache,
            facts_cache,
            index_url,
            distribution,
            versions,
            value,
        ),
    )

def _cache_get(cache, facts, index_url, distribution, versions):
    if not facts:
        return cache.get(index_url, distribution, versions)

    if versions:
        cached = facts.get(index_url, distribution, versions)
        if cached:
            return cached

    cached = cache.get(index_url, distribution, versions)
    if not cached:
        return None

    # Ensure that we write back to the facts, this happens if we request versions that
    # we don't have facts for but we have in-memory cache of SimpleAPI query results
    if versions:
        facts.setdefault(index_url, distribution, cached)
    return cached

def _cache_setdefault(cache, facts, index_url, distribution, versions, value):
    filtered = cache.setdefault(index_url, distribution, versions, value)

    if facts and versions:
        facts.setdefault(index_url, distribution, filtered)

    return filtered

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
        get = lambda index_url, distribution, versions: _memcache_get(
            cache,
            index_url,
            distribution,
            versions,
        ),
        setdefault = lambda index_url, distribution, versions, value: _memcache_setdefault(
            cache,
            index_url,
            distribution,
            versions,
            value,
        ),
    )

def _vkey(versions):
    if not versions:
        return ""

    if len(versions) == 1:
        if type(versions) == "dict":
            return versions.keys()[0]
        else:
            return versions[0]

    return ",".join(sorted(versions))

def _memcache_get(cache, index_url, distribution, versions):
    if not versions:
        return cache.get((index_url, distribution, ""))

    vkey = _vkey(versions)
    filtered = cache.get((index_url, distribution, vkey))
    if filtered:
        return filtered

    unfiltered = cache.get((index_url, distribution, ""))
    if not unfiltered:
        return None

    filtered = _filter_packages(unfiltered, versions, index_url, distribution)
    cache.setdefault((index_url, distribution, vkey), filtered)
    return filtered

def _memcache_setdefault(cache, index_url, distribution, versions, value):
    cache.setdefault((index_url, distribution, ""), value)
    if not versions:
        return value

    filtered = _filter_packages(value, versions, index_url, distribution)

    vkey = _vkey(versions)
    cache.setdefault((index_url, distribution, vkey), filtered)
    return filtered

def _filter_packages(dists, requested_versions, index_url, distribution):
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

        sdists[sha256] = _with_absolute_url(d, index_url, distribution)
        sha256s_by_version.setdefault(d.version, []).append(sha256)

    for sha256, d in dists.whls.items():
        if d.version not in requested_versions:
            continue

        whls[sha256] = _with_absolute_url(d, index_url, distribution)
        sha256s_by_version.setdefault(d.version, []).append(sha256)

    if not whls and not sdists:
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
        get = lambda index_url, distribution, versions: _get_from_facts(
            facts,
            known_facts,
            index_url,
            distribution,
            versions,
            facts_version,
        ),
        setdefault = lambda url, distribution, value: _store_facts(facts, facts_version, url, value),
        known_facts = known_facts,
        facts = facts,
    )

def _get_from_facts(facts, known_facts, index_url, distribution, requested_versions, facts_version):
    if known_facts.get("fact_version") != facts_version:
        # cannot trust known facts, different version that we know how to parse
        return None

    known_sources = {}

    known_facts = known_facts.get(index_url, {})

    index_url_for_distro = "{}/{}/".format(index_url, distribution)
    for url, sha256 in known_facts.get("dist_hashes", {}).items():
        filename = known_facts.get("dist_filenames", {}).get(sha256)
        if not filename:
            _, _, filename = url.rpartition("/")

        version = pkg_version(filename, distribution)
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
            url = absolute_url(index_url = index_url_for_distro, url = url),
            yanked = known_facts.get("dist_yanked", {}).get(sha256, False),
        ))

    if not known_sources:
        return None

    output = struct(
        whls = known_sources.get("whls", {}),
        sdists = known_sources.get("sdists", {}),
        sha256s_by_version = known_sources.get("sha256s_by_version", {}),
    )
    _store_facts(facts, facts_version, index_url, output)
    return output

def _with_absolute_url(d, index_url, distribution):
    index_url_for_distro = "{}/{}/".format(index_url.rstrip("/"), distribution)

    # TODO @aignas 2026-02-08: think of a better way to do this
    # TODO @aignas 2026-02-08: if the url is absolute, return d
    kwargs = dict()
    for attr in [
        "sha256",
        "filename",
        "version",
        "metadata_sha256",
        "metadata_url",
        "yanked",
        "url",
    ]:
        if hasattr(d, attr):
            kwargs[attr] = getattr(d, attr)
            if attr == "url":
                kwargs[attr] = absolute_url(index_url = index_url_for_distro, url = kwargs[attr])

    return struct(**kwargs)

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

    # Store the distributions by index URL that we find them on.
    facts = facts.setdefault(index_url, {})

    for sha256, d in (value.sdists | value.whls).items():
        facts.setdefault("dist_hashes", {}).setdefault(d.url, sha256)
        if not d.url.endswith(d.filename):
            facts.setdefault("dist_filenames", {}).setdefault(d.url, d.filename)
        if d.yanked:
            # TODO @aignas 2026-01-21: store yank reason
            facts.setdefault("dist_yanked", {}).setdefault(sha256, True)

    return value
