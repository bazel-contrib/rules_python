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

load("//python/private:auth.bzl", _get_auth = "get_auth")
load("//python/private:envsubst.bzl", "envsubst")
load("//python/private:normalize_name.bzl", "normalize_name")
load(":parse_simpleapi_html.bzl", "parse_simpleapi_html")
load(":urllib.bzl", "urllib")

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

    First it queries all of the indexes for available packages and then it downloads the contents of
    the per-package URLs and sha256 values. This is to enable us to use bazel_downloader with
    `requirements.txt` files. As a side effect we also are able to "cross-compile" by fetching the
    right wheel for the right target platform through the information that we retrieve here.

    Args:
        ctx: The module_ctx or repository_ctx.
        attr: Contains the parameters for the download. They are grouped into a
          struct for better clarity. It must have attributes:
           * index_url: str, the index, or if `extra_index_urls` are passed, the default index.
           * index_url_overrides: dict[str, str], the index overrides for separate packages.
           * extra_index_urls: Will be looked at in the order they are defined and the first match
                wins. This is similar to what uv does, see
                https://docs.astral.sh/uv/concepts/indexes/#searching-across-multiple-indexes.
                PRs for implementing other strategies are welcome.
           * sources: list[str], the sources to download things for. Each value is
             the contents of requirements files.
           * envsubst: list[str], the envsubst vars for performing substitution in index url.
           * netrc: The netrc parameter for ctx.download, see http_file for docs.
           * auth_patterns: The auth_patterns parameter for ctx.download, see
               http_file for docs.
        cache: An opaque object used to cache call results. For implementation
            see ./pypi_cache.bzl file. We use the canonical_id parameter for the key
            value to ensure that distribution fetches from different indexes do not cause
            cache collisions, because the index may return different locations from where
            the files should be downloaded. We are not using the built-in cache in the
            `download` function because the index may get updated at any time and we need
            to be able to refresh the data.
        parallel_download: A boolean to enable usage of bazel 7.1 non-blocking downloads.
        read_simpleapi: a function for reading and parsing of the SimpleAPI contents.
            Used in tests.
        get_auth: A function to get auth information passed to read_simpleapi. Used in tests.
        _fail: a function to print a failure. Used in tests.

    Returns:
        dict of pkg name to the parsed HTML contents - a list of structs.
    """
    if not attr.sources:
        return {}

    index_url_overrides = {
        normalize_name(p): i
        for p, i in (attr.index_url_overrides or {}).items()
    }
    sources = {
        normalize_name(pkg): versions
        for pkg, versions in attr.sources.items()
    }

    read_simpleapi = read_simpleapi or _read_simpleapi

    ctx.report_progress("Fetch package lists from PyPI index")

    # NOTE: we are not merging results from multiple indexes to replicate how `pip` would
    # handle this case. What we do is we select a particular index to download the packages
    dist_urls = _get_dist_urls(
        ctx,
        default_index = attr.index_url,
        index_urls = attr.extra_index_urls,
        index_url_overrides = index_url_overrides,
        sources = sources,
        read_simpleapi = read_simpleapi,
        cache = cache,
        get_auth = get_auth,
        attr = attr,
        block = not parallel_download,
        _fail = _fail,
    )

    ctx.report_progress("Fetching package URLs from PyPI index")

    downloads = {}
    contents = {}
    for pkg, url in dist_urls.items():
        result = read_simpleapi(
            ctx = ctx,
            attr = attr,
            url = url,
            cache = cache,
            versions = sources[pkg],
            get_auth = get_auth,
            block = not parallel_download,
            parse_index = False,
        )
        if hasattr(result, "wait"):
            # We will process it in a separate loop:
            downloads[pkg] = result
        else:
            contents[pkg] = _with_index_url(url, result.output)

    for pkg, d in downloads.items():
        # If we use `block` == False, then we need to have a second loop that is
        # collecting all of the results as they were being downloaded in parallel.
        contents[pkg] = _with_index_url(dist_urls[pkg], d.wait().output)

    return contents

def _get_dist_urls(ctx, *, default_index, index_urls, index_url_overrides, sources, read_simpleapi, attr, block, _fail = fail, **kwargs):
    if index_url_overrides:
        # Let's not call the index at all and just assume that all of the overrides have been
        # specified.
        return {
            pkg: _normalize_url("{}/{}/".format(
                index_url_overrides.get(pkg, default_index),
                pkg.replace("_", "-"),  # Use the official normalization for URLs
            ))
            for pkg in sources
        }

    downloads = {}
    results = {}

    # Ensure the value is not frozen
    index_urls = [] + (index_urls or [])
    if default_index not in index_urls:
        index_urls.append(default_index)

    for index_url in index_urls:
        download = read_simpleapi(
            ctx = ctx,
            attr = attr,
            url = _normalize_url("{index_url}/".format(index_url = index_url)),
            parse_index = True,
            versions = {pkg: None for pkg in sources},
            block = block,
            **kwargs
        )
        if hasattr(download, "wait"):
            downloads[index_url] = download
        else:
            results[index_url] = download

    for index_url, download in downloads.items():
        results[index_url] = download.wait()

    found_on_index = {}
    for index_url, result in results.items():
        for pkg in sources:
            if pkg in found_on_index:
                # We have already found the package, skip searching for it in
                # other indexes.
                #
                # If we wanted to merge all of the index results, we would have to continue here
                # and in the outer function process merging of the results.
                continue

            found = result.output.get(pkg)
            if not found:
                continue

            # Ignore the URL here because we know how to construct it.

            found_on_index[pkg] = _normalize_url("{}/{}/".format(
                index_url,
                pkg.replace("_", "-"),  # Use the official normalization for URLs
            ))

    return found_on_index

def _normalize_url(url):
    return urllib.strip_empty_path_segments(url)

def _read_simpleapi(ctx, url, attr, cache, versions, parse_index, get_auth = None, **download_kwargs):
    """Read SimpleAPI.

    Args:
        ctx: The module_ctx or repository_ctx.
        url: {type}`str`, the url parameter that can be passed to ctx.download.
        attr: The attribute that contains necessary info for downloading. The
          following attributes must be present:
           * envsubst: {type}`dict[str, str]` for performing substitutions in the URL.
           * netrc: The netrc parameter for ctx.download, see {obj}`http_file` for docs.
           * auth_patterns: The auth_patterns parameter for ctx.download, see
               {obj}`http_file` for docs.
        cache: {type}`struct` the `pypi_cache` instance.
        versions: {type}`list[str] The versions that have been requested.
        get_auth: A function to get auth information. Used in tests.
        parse_index:  {type}`bool` Whether to parse the content as a root index page
            (e.g. `/simple/`) instead of a package-specific page.
        **download_kwargs: Any extra params to ctx.download.
            Note that output and auth will be passed for you.

    Returns:
        A similar object to what `download` would return except that in result.out
        will be the parsed simple api contents.
    """
    real_url = _normalize_url(envsubst(url, attr.envsubst, ctx.getenv))

    cache_key = (url, real_url, versions)
    cached_result = cache.get(cache_key)
    if cached_result:
        return struct(success = True, output = cached_result)

    output_str = envsubst(
        url,
        attr.envsubst,
        # Use env names in the subst values - this will be unique over
        # the lifetime of the execution of this function and we also use
        # `~` as the separator to ensure that we don't get clashes.
        {e: "~{}~".format(e) for e in attr.envsubst}.get,
    )

    # Transform the URL into a valid filename
    for char in [".", ":", "/", "\\", "-"]:
        output_str = output_str.replace(char, "_")

    output = ctx.path(output_str.strip("_").lower() + ".html")

    get_auth = get_auth or _get_auth

    # NOTE: this may have block = True or block = False in the download_kwargs
    download = ctx.download(
        url = [real_url],
        output = output,
        auth = get_auth(ctx, [real_url], ctx_attr = attr),
        **download_kwargs
    )

    if download_kwargs.get("block") == False:
        # Simulate the same API as ctx.download has
        return struct(
            wait = lambda: _read_index_result(
                ctx,
                result = download.wait(),
                output = output,
                cache = cache,
                cache_key = cache_key,
                parse_index = parse_index,
            ),
        )

    return _read_index_result(
        ctx,
        result = download,
        output = output,
        cache = cache,
        cache_key = cache_key,
        parse_index = parse_index,
    )

def _read_index_result(ctx, *, result, output, cache, cache_key, parse_index):
    if not result.success:
        return struct(success = False)

    content = ctx.read(output)

    output = parse_simpleapi_html(content = content, parse_index = parse_index)
    if output:
        cache.setdefault(cache_key, output)
        return struct(success = True, output = output)
    else:
        return struct(success = False)

def _with_index_url(index_url, values):
    if not values:
        return values

    return struct(
        sdists = values.sdists,
        whls = values.whls,
        sha256s_by_version = values.sha256s_by_version,
        index_url = index_url,
    )
