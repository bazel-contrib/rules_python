"""Utilities for getting an absolute URL from index_url and the URL we find on PyPI index."""

load("//python/private:envsubst.bzl", _envsubst = "envsubst")

def _get_root_directory(url):
    scheme_end = url.find("://")
    if scheme_end == -1:
        fail("Invalid URL format: '{}'".format(url))

    scheme = url[:scheme_end]
    host_end = url.find("/", scheme_end + 3)
    if host_end == -1:
        host_end = len(url)
    host = url[scheme_end + 3:host_end]

    return "{}://{}".format(scheme, host)

def _is_downloadable(url):
    """Checks if the URL would be accepted by the Bazel downloader.

    This is based on Bazel's HttpUtils::isUrlSupportedByDownloader
    """
    return url.startswith("http://") or url.startswith("https://") or url.startswith("file://")

def _absolute_url(index_url, candidate):
    """Convert into an absolute URL.

    Args:
        index_url: The index URL where the file has been found.
        candidate: The candidate URL which may be not absolute.

    Returns:
        An absolute URL
    """
    if candidate == "":
        return candidate

    if _is_downloadable(candidate):
        return candidate

    if candidate.startswith("/"):
        # absolute path
        root_directory = _get_root_directory(index_url)
        return "{}{}".format(root_directory, candidate)

    if candidate.startswith(".."):
        # relative path with up references
        candidate_parts = candidate.split("..")
        last = candidate_parts[-1]
        for _ in range(len(candidate_parts) - 1):
            index_url, _, _ = index_url.rstrip("/").rpartition("/")

        return "{}/{}".format(index_url, last.strip("/"))

    # relative path without up-references
    return "{}/{}".format(index_url.rstrip("/"), candidate)

def _with_envsubst(url, envsubst = None, getenv = None):
    if not url or not envsubst or not getenv:
        return url

    return _envsubst(url, envsubst, getenv)

def _strip_empty_path_segments(url):
    """Removes empty path segments from a URL. Does nothing for urls with no scheme.

    Public only for testing.

    Args:
        url: The url to remove empty path segments from

    Returns:
        The url with empty path segments removed and any trailing slash preserved.
        If the url had no scheme it is returned unchanged.
    """
    sep = "://"
    scheme, _, rest = url.partition(sep)
    if scheme.lower() == "file" and rest.startswith("/"):
        sep = sep + "/"
        rest = rest[1:]

    if rest == "":
        return url
    stripped = "/".join([p for p in rest.split("/") if p])
    if url.endswith("/"):
        return "{}{}{}/".format(scheme, sep, stripped)
    else:
        return "{}{}{}".format(scheme, sep, stripped)

urllib = struct(
    is_absolute = _is_downloadable,
    # Ensure that we strip empty path segments when making an absolute URL
    absolute_url = lambda index_url, candidate, *, envsubst = None, getenv = None: _strip_empty_path_segments(_with_envsubst(_absolute_url(index_url, candidate), envsubst, getenv)),
    strip_empty_path_segments = _strip_empty_path_segments,
)
