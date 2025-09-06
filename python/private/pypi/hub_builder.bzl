"""A hub repository builder for incrementally building the hub configuration."""

load("//python/private:normalize_name.bzl", "normalize_name")

def hub_builder(
        *,
        name,
        module_name,
        simpleapi_download_fn,
        simpleapi_cache = {}):
    """Return a hub builder instance"""

    # buildifier: disable=uninitialized
    self = struct(
        name = name,
        module_name = module_name,
        python_versions = [],
        _simpleapi_download_fn = simpleapi_download_fn,
        _simpleapi_cache = simpleapi_cache,
        # keep sorted
        add = lambda *args, **kwargs: _add(self, *args, **kwargs),
        get_index_urls = lambda *args, **kwargs: _get_index_urls(self, *args, **kwargs),
    )

    # buildifier: enable=uninitialized
    return self

def _add(self, *, python_version):
    if python_version in self.python_versions:
        fail((
            "Duplicate pip python version '{version}' for hub " +
            "'{hub}' in module '{module}': the Python versions " +
            "used for a hub must be unique"
        ).format(
            hub = self.name,
            module = self.module_name,
            version = python_version,
        ))

    self.python_versions.append(python_version)

def _get_index_urls(self, pip_attr):
    get_index_urls = None
    if pip_attr.experimental_index_url:
        skip_sources = [
            normalize_name(s)
            for s in pip_attr.simpleapi_skip
        ]
        get_index_urls = lambda ctx, distributions: self._simpleapi_download_fn(
            ctx,
            attr = struct(
                index_url = pip_attr.experimental_index_url,
                extra_index_urls = pip_attr.experimental_extra_index_urls or [],
                index_url_overrides = pip_attr.experimental_index_url_overrides or {},
                sources = [
                    d
                    for d in distributions
                    if normalize_name(d) not in skip_sources
                ],
                envsubst = pip_attr.envsubst,
                # Auth related info
                netrc = pip_attr.netrc,
                auth_patterns = pip_attr.auth_patterns,
            ),
            cache = self._simpleapi_cache,
            parallel_download = pip_attr.parallel_download,
        )
    elif pip_attr.experimental_extra_index_urls:
        fail("'experimental_extra_index_urls' is a no-op unless 'experimental_index_url' is set")
    elif pip_attr.experimental_index_url_overrides:
        fail("'experimental_index_url_overrides' is a no-op unless 'experimental_index_url' is set")

    return get_index_urls
