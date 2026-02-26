"""A cache for the PyPI index contents evaluation.

This is design to work as the following:
- in-memory cache for results of PyPI index queries, so that we are not calling PyPI multiple times
  for the same package for different hub repos.

In the future the same will be used to:
- Store PyPI index query results as facts in the MODULE.bazel.lock file
"""

def pypi_cache():
    """The cache for PyPI index queries."""
    self = struct(
        store = {},
    )

    return struct(
        setdefault = lambda key, parsed_result: _pypi_cache_setdefault(self, key, parsed_result),
        get = lambda key: _pypi_cache_get(self, key),
    )

def _pypi_cache_setdefault(self, key, parsed_result):
    """Store the value if not yet cached.

    Args:
        self: {type}`struct` The self of this implementation.
        key: {type}`str` The cache key, can be any string.
        parsed_result: {type}`struct` The result of `parse_simpleapi_html` function.

    Returns:
        The `parse_result`.
    """
    return self.store.setdefault(key, parsed_result)

def _pypi_cache_get(self, key):
    """Return the parsed result from the cache.

    Args:
        self: {type}`struct` The self of this implementation.
        key: {type}`str` The cache key, can be any string.

    Returns:
        The {type}`struct` or `None` based on if the result is in the cache or not.
    """
    return self.store.get(key)
