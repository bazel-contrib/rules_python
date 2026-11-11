""

load("@rules_testing//lib:test_suite.bzl", "test_suite")
load("@rules_testing//lib:truth.bzl", "subjects")
load("//python/private/pypi:pypi_cache.bzl", "pypi_cache")  # buildifier: disable=bzl-visibility
load("//tests/support/mocks:mocks.bzl", "mocks")

_tests = []

def _cache(env, **kwargs):
    cache = pypi_cache(**kwargs)

    attrs = {
        "hashes_by_version": subjects.dict,
        "sdists": subjects.dict,
        "whls": subjects.dict,
    }

    def _expect(value):
        if not value:
            return env.expect.that_str(value)

        if type(value) == "dict":
            return env.expect.that_dict(value)

        return env.expect.that_struct(
            value,
            attrs = attrs,
        )

    return struct(
        setdefault = lambda *args, **kwargs: _expect(
            cache.setdefault(*args, **kwargs),
        ),
        get = lambda *args, **kwargs: _expect(
            cache.get(*args, **kwargs),
        ),
        raw_facts = lambda: cache.get_facts(),
        expect_facts = lambda: env.expect.that_dict(cache.get_facts()),
    )

def _test_memory_cache_hit(env):
    """Verifies that the cache returns stored values for the same real_url."""
    store = {}

    # We pass None for module_ctx to focus solely on memory_cache behavior
    cache = _cache(env, mctx = None, store = store)

    # Mocked parsed result from a PyPI-like index
    fake_result = struct(
        sdists = {
            "sha256:sha_1": struct(version = "1.0.0", filename = "pkg-1.0.0.tar.gz"),
        },
        whls = {
            "sha256:sha_2": struct(version = "1.1.0", filename = "pkg-1.1.0-py3-none-any.whl"),
        },
        hashes_by_version = {
            "1.0.0": ["sha256:sha_1"],
            "1.1.0": ["sha256:sha_2"],
        },
    )

    # Key format: (index_url, real_url, versions)
    key = ("https://{PYPI_INDEX_URL}/pkg", "https://pypi.org/simple/pkg", ["1.0.0", "1.1.0"])

    # When set the cache
    cache.setdefault(key, fake_result)

    # And get a value back
    got = cache.get(key)

    got.sdists().contains_exactly(fake_result.sdists)
    got.whls().contains_exactly(fake_result.whls)
    got.hashes_by_version().contains_exactly(fake_result.hashes_by_version)

    # A different key with fewer versions
    key = ("https://{PYPI_INDEX_URL}/pkg", "https://pypi.org/simple/pkg", ["1.0.0"])

    got = cache.get(key)
    got.sdists().contains_exactly(fake_result.sdists)
    got.whls().contains_exactly({})
    got.hashes_by_version().contains_exactly({"1.0.0": ["sha256:sha_1"]})

    # A key with no matches
    key = ("https://{PYPI_INDEX_URL}/pkg", "https://pypi.org/simple/pkg", ["1.2.0"])

    cache.get(key).equals(None)

_tests.append(_test_memory_cache_hit)

def _test_pypi_cache_writes_to_facts(env):
    """Verifies that setting a value in the cache also populates the facts store."""
    mock_ctx = mocks.mctx(facts = {})
    cache = _cache(env, mctx = mock_ctx)

    fake_result = struct(
        sdists = {
            "sha256:sha_sdist": struct(
                version = "1.0.0",
                filename = "pkg-1.0.0.tar.gz",
                url = "https://pypi.org/files/pkg-1.0.0.tar.gz",
                digest = "sha256:sha_sdist",
                yanked = None,
            ),
        },
        whls = {
            "sha256:sha_whl": struct(
                version = "1.0.0",
                filename = "pkg-1.0.0-py3-none-any.whl",
                url = "https://pypi.org/files/pkg-1.0.0-py3-none-any.whl",
                digest = "sha256:sha_whl",
                yanked = "Security issue",
            ),
            # This won't get stored
            "sha256:sha_whl_2": struct(
                version = "1.1.0",
                filename = "pkg-1.1.0-py3-none-any.whl",
                url = "https://pypi.org/files/pkg-1.1.0-py3-none-any.whl",
                digest = "sha256:sha_whl_2",
                yanked = None,
            ),
        },
        hashes_by_version = {
            "1.0.0": ["sha256:sha_sdist", "sha256:sha_whl"],
            "1.1.0": ["sha256:sha_whl_2"],
        },
    )

    key = ("https://{PYPI_INDEX_URL}/pkg/", "https://pypi.org/simple/pkg/", ["1.0.0"])

    # When we set the cache
    cache.setdefault(key, fake_result)

    # Then the key returns us the same items
    got = cache.get(key)
    got.whls().contains_exactly({
        "sha256:sha_whl": fake_result.whls["sha256:sha_whl"],
    })
    got.sdists().contains_exactly(fake_result.sdists)
    got.hashes_by_version().contains_exactly({
        "1.0.0": fake_result.hashes_by_version["1.0.0"],
    })

    # Then when we get facts at the end
    cache.expect_facts().contains_exactly({
        "fact_version": "v5",  # Facts version
        "pkg@https://{PYPI_INDEX_URL}": {
            "https://pypi.org/files/": {
                "pkg-1.0.0-py3-none-any.whl": "sha256:sha_whl||Security issue",
                "pkg-1.0.0.tar.gz": "sha256:sha_sdist",
            },
        },
    })

    # When we get the other items cached in memory, they get written to facts
    got = cache.get((key[0], key[1], ["1.1.0"]))
    got.whls().contains_exactly({
        "sha256:sha_whl_2": fake_result.whls["sha256:sha_whl_2"],
    })
    got.sdists().contains_exactly({})
    got.hashes_by_version().contains_exactly({
        "1.1.0": fake_result.hashes_by_version["1.1.0"],
    })

    # Then when we get facts at the end
    cache.expect_facts().contains_exactly({
        "fact_version": "v5",  # Facts version
        "pkg@https://{PYPI_INDEX_URL}": {
            "https://pypi.org/files/": {
                "pkg-1.0.0-py3-none-any.whl": "sha256:sha_whl||Security issue",
                "pkg-1.0.0.tar.gz": "sha256:sha_sdist",
                "pkg-1.1.0-py3-none-any.whl": "sha256:sha_whl_2",
            },
        },
    })

_tests.append(_test_pypi_cache_writes_to_facts)

def _test_pypi_cache_reads_from_facts(env):
    """Verifies that setting a value in the cache also populates the facts store."""
    mock_ctx = mocks.mctx(facts = {
        "fact_version": "v5",  # Facts version
        "pkg@https://{PYPI_INDEX_URL}": {
            "https://pypi.org/files/": {
                "pkg-1.0.0-py3-none-any.whl": "sha256:sha_whl||Security issue",
                "pkg-1.0.0.tar.gz": "sha256:sha_sdist",
            },
        },
    })
    cache = _cache(env, mctx = mock_ctx)

    key = ("https://{PYPI_INDEX_URL}/pkg/", "https://pypi.org/simple/pkg/", ["1.0.0"])

    # Then we would get empty facts because we haven't accessed any of the known facts.
    # This simulates the dropping of the facts of requirements that are no longer needed.
    cache.expect_facts().contains_exactly({})

    # When we get the
    got = cache.get(key)

    expected_result = struct(
        sdists = {
            "sha256:sha_sdist": struct(
                digest = "sha256:sha_sdist",
                version = "1.0.0",
                filename = "pkg-1.0.0.tar.gz",
                metadata_url = "",
                metadata_sha256 = "",
                url = "https://pypi.org/files/pkg-1.0.0.tar.gz",
                yanked = None,
            ),
        },
        whls = {
            "sha256:sha_whl": struct(
                digest = "sha256:sha_whl",
                version = "1.0.0",
                filename = "pkg-1.0.0-py3-none-any.whl",
                url = "https://pypi.org/files/pkg-1.0.0-py3-none-any.whl",
                metadata_url = "",
                metadata_sha256 = "",
                yanked = "Security issue",
            ),
        },
        hashes_by_version = {
            "1.0.0": ["sha256:sha_sdist", "sha256:sha_whl"],
        },
    )

    got.whls().contains_exactly(expected_result.whls)
    got.sdists().contains_exactly(expected_result.sdists)
    got.hashes_by_version().contains_exactly(expected_result.hashes_by_version)

    # Then when we store the same facts back again, because we accessed the cached keys.
    cache.expect_facts().contains_exactly(mock_ctx.facts)

    # When we request more than what we have, we will return nothing
    key = ("https://{PYPI_INDEX_URL}/pkg/", "https://pypi.org/simple/pkg/", ["1.0.0", "1.1.0"])
    got = cache.get(key)
    got.equals(None)

_tests.append(_test_pypi_cache_reads_from_facts)

def _test_pypi_cache_facts_different_filename(env):
    """Verifies that distributions with a filename different from the URL filename are handled correctly."""
    mock_ctx = mocks.mctx(facts = {})
    cache = _cache(env, mctx = mock_ctx)

    fake_result = struct(
        sdists = {
            "sha256:sha_custom": struct(
                version = "1.0.0",
                filename = "custom-pkg-1.0.0.tar.gz",
                url = "https://pypi.org/files/pkg-1.0.0.tar.gz",
                digest = "sha256:sha_custom",
                yanked = None,
            ),
        },
        whls = {},
        hashes_by_version = {
            "1.0.0": ["sha256:sha_custom"],
        },
    )

    key = ("https://{PYPI_INDEX_URL}/pkg/", "https://pypi.org/simple/pkg/", ["1.0.0"])
    cache.setdefault(key, fake_result)

    # Verify facts store includes the custom filename separated by pipe
    cache.expect_facts().contains_exactly({
        "fact_version": "v5",
        "pkg@https://{PYPI_INDEX_URL}": {
            "https://pypi.org/files/": {
                "pkg-1.0.0.tar.gz": "sha256:sha_custom|custom-pkg-1.0.0.tar.gz",
            },
        },
    })

    # Verify reading back from facts reconstructs the correct filename
    cache2 = _cache(env, mctx = mocks.mctx(facts = cache.raw_facts()))
    got = cache2.get(key)
    got.sdists().contains_exactly({
        "sha256:sha_custom": struct(
            digest = "sha256:sha_custom",
            version = "1.0.0",
            filename = "custom-pkg-1.0.0.tar.gz",
            metadata_url = "",
            metadata_sha256 = "",
            url = "https://pypi.org/files/pkg-1.0.0.tar.gz",
            yanked = None,
        ),
    })

_tests.append(_test_pypi_cache_facts_different_filename)

def _test_pypi_cache_reads_from_facts_drops_unaccessed_dists(env):
    """Verifies that dists for unaccessed versions are dropped from computed facts."""
    mock_ctx = mocks.mctx(facts = {
        "fact_version": "v5",
        "pkg@https://{PYPI_INDEX_URL}": {
            "https://pypi.org/files/": {
                "pkg-1.0.0-py3-none-any.whl": "sha256:sha_whl_1.0.0",
                "pkg-1.0.0.tar.gz": "sha256:sha_sdist_1.0.0",
                "pkg-1.1.0-py3-none-any.whl": "sha256:sha_whl_1.1.0",
                "pkg-1.1.0.tar.gz": "sha256:sha_sdist_1.1.0",
            },
        },
    })
    cache = _cache(env, mctx = mock_ctx)

    # Request only version 1.0.0; version 1.1.0 is NOT requested
    key = ("https://{PYPI_INDEX_URL}/pkg/", "https://pypi.org/simple/pkg/", ["1.0.0"])
    got = cache.get(key)

    expected = struct(
        sdists = {
            "sha256:sha_sdist_1.0.0": struct(
                digest = "sha256:sha_sdist_1.0.0",
                version = "1.0.0",
                filename = "pkg-1.0.0.tar.gz",
                metadata_url = "",
                metadata_sha256 = "",
                url = "https://pypi.org/files/pkg-1.0.0.tar.gz",
                yanked = None,
            ),
        },
        whls = {
            "sha256:sha_whl_1.0.0": struct(
                digest = "sha256:sha_whl_1.0.0",
                version = "1.0.0",
                filename = "pkg-1.0.0-py3-none-any.whl",
                metadata_url = "",
                metadata_sha256 = "",
                url = "https://pypi.org/files/pkg-1.0.0-py3-none-any.whl",
                yanked = None,
            ),
        },
        hashes_by_version = {
            "1.0.0": ["sha256:sha_sdist_1.0.0", "sha256:sha_whl_1.0.0"],
        },
    )
    got.whls().contains_exactly(expected.whls)
    got.sdists().contains_exactly(expected.sdists)
    got.hashes_by_version().contains_exactly(expected.hashes_by_version)

    # get_facts() must only contain version 1.0.0 data; 1.1.0 is dropped
    cache.expect_facts().contains_exactly({
        "fact_version": "v5",
        "pkg@https://{PYPI_INDEX_URL}": {
            "https://pypi.org/files/": {
                "pkg-1.0.0-py3-none-any.whl": "sha256:sha_whl_1.0.0",
                "pkg-1.0.0.tar.gz": "sha256:sha_sdist_1.0.0",
            },
        },
    })

_tests.append(_test_pypi_cache_reads_from_facts_drops_unaccessed_dists)

def _test_pypi_cache_facts_non_sha256_round_trip(env):
    """Verifies that digests of other hash algorithms survive the facts round trip."""
    mock_ctx = mocks.mctx(facts = {})
    cache = _cache(env, mctx = mock_ctx)

    fake_result = struct(
        sdists = {},
        whls = {
            "sha512:whl_digest": struct(
                version = "1.0.0",
                filename = "pkg-1.0.0-py3-none-any.whl",
                url = "https://pypi.org/files/pkg-1.0.0-py3-none-any.whl",
                digest = "sha512:whl_digest",
                yanked = None,
            ),
        },
        hashes_by_version = {
            "1.0.0": ["sha512:whl_digest"],
        },
    )

    key = ("https://{PYPI_INDEX_URL}/pkg/", "https://pypi.org/simple/pkg/", ["1.0.0"])
    cache.setdefault(key, fake_result)

    # The hash algorithm is stored in the facts
    cache.expect_facts().contains_exactly({
        "fact_version": "v5",  # Facts version
        "pkg@https://{PYPI_INDEX_URL}": {
            "https://pypi.org/files/": {
                "pkg-1.0.0-py3-none-any.whl": "sha512:whl_digest",
            },
        },
    })

    # And a cache that only has the facts reconstructs the digests
    cache = _cache(env, mctx = mocks.mctx(facts = {
        "fact_version": "v5",  # Facts version
        "pkg@https://{PYPI_INDEX_URL}": {
            "https://pypi.org/files/": {
                "pkg-1.0.0-py3-none-any.whl": "sha512:whl_digest",
            },
        },
    }))

    got = cache.get(key)
    got.whls().contains_exactly({
        "sha512:whl_digest": struct(
            digest = "sha512:whl_digest",
            version = "1.0.0",
            filename = "pkg-1.0.0-py3-none-any.whl",
            metadata_url = "",
            metadata_sha256 = "",
            url = "https://pypi.org/files/pkg-1.0.0-py3-none-any.whl",
            yanked = None,
        ),
    })
    got.hashes_by_version().contains_exactly({"1.0.0": ["sha512:whl_digest"]})

_tests.append(_test_pypi_cache_facts_non_sha256_round_trip)

def _test_pypi_cache_facts_round_trip_all_entry_shapes(env):
    """Verifies that every compact entry shape survives the facts round trip."""
    mock_ctx = mocks.mctx(facts = {})
    cache = _cache(env, mctx = mock_ctx)

    fake_result = struct(
        sdists = {
            "sha256:default_sdist": struct(
                version = "1.0.0",
                filename = "pkg-1.0.0.tar.gz",
                url = "https://pypi.org/files/pkg-1.0.0.tar.gz",
                digest = "sha256:default_sdist",
                yanked = None,
            ),
            "sha256:yanked_sdist": struct(
                version = "1.0.0",
                filename = "pkg-1.0.0.zip",
                url = "https://pypi.org/files/pkg-1.0.0.zip",
                digest = "sha256:yanked_sdist",
                yanked = "Security issue | use 2.0.0",
            ),
        },
        whls = {
            "sha256:custom_whl": struct(
                version = "1.0.0",
                filename = "custom_pkg-1.0.0-py3-none-any.whl",
                url = "https://pypi.org/files/download/custom.whl",
                digest = "sha256:custom_whl",
                yanked = None,
            ),
            "sha256:custom_yanked_whl": struct(
                version = "1.0.0",
                filename = "custom_yanked_pkg-1.0.0-py3-none-any.whl",
                url = "https://pypi.org/files/download/custom-yanked.whl",
                digest = "sha256:custom_yanked_whl",
                yanked = "Yanked for testing",
            ),
        },
        hashes_by_version = {
            "1.0.0": [
                "sha256:custom_whl",
                "sha256:custom_yanked_whl",
                "sha256:default_sdist",
                "sha256:yanked_sdist",
            ],
        },
    )

    key = ("https://{PYPI_INDEX_URL}/pkg/", "https://pypi.org/simple/pkg/", ["1.0.0"])
    cache.setdefault(key, fake_result)

    cache.expect_facts().contains_exactly({
        "fact_version": "v5",
        "pkg@https://{PYPI_INDEX_URL}": {
            "https://pypi.org/files/": {
                "download/custom-yanked.whl": "sha256:custom_yanked_whl|custom_yanked_pkg-1.0.0-py3-none-any.whl|Yanked for testing",
                "download/custom.whl": "sha256:custom_whl|custom_pkg-1.0.0-py3-none-any.whl",
                "pkg-1.0.0.tar.gz": "sha256:default_sdist",
                "pkg-1.0.0.zip": "sha256:yanked_sdist||Security issue | use 2.0.0",
            },
        },
    })

    cache2 = _cache(env, mctx = mocks.mctx(facts = cache.raw_facts()))
    got = cache2.get(key)
    got.sdists().contains_exactly({
        "sha256:default_sdist": struct(
            digest = "sha256:default_sdist",
            version = "1.0.0",
            filename = "pkg-1.0.0.tar.gz",
            metadata_url = "",
            metadata_sha256 = "",
            url = "https://pypi.org/files/pkg-1.0.0.tar.gz",
            yanked = None,
        ),
        "sha256:yanked_sdist": struct(
            digest = "sha256:yanked_sdist",
            version = "1.0.0",
            filename = "pkg-1.0.0.zip",
            metadata_url = "",
            metadata_sha256 = "",
            url = "https://pypi.org/files/pkg-1.0.0.zip",
            yanked = "Security issue | use 2.0.0",
        ),
    })
    got.whls().contains_exactly({
        "sha256:custom_whl": struct(
            digest = "sha256:custom_whl",
            version = "1.0.0",
            filename = "custom_pkg-1.0.0-py3-none-any.whl",
            metadata_url = "",
            metadata_sha256 = "",
            url = "https://pypi.org/files/download/custom.whl",
            yanked = None,
        ),
        "sha256:custom_yanked_whl": struct(
            digest = "sha256:custom_yanked_whl",
            version = "1.0.0",
            filename = "custom_yanked_pkg-1.0.0-py3-none-any.whl",
            metadata_url = "",
            metadata_sha256 = "",
            url = "https://pypi.org/files/download/custom-yanked.whl",
            yanked = "Yanked for testing",
        ),
    })
    got.hashes_by_version().contains_exactly(fake_result.hashes_by_version)

_tests.append(_test_pypi_cache_facts_round_trip_all_entry_shapes)

def _test_pypi_cache_facts_round_trip_edge_cases(env):
    """Verifies the facts round trip for empty digests, empty yank reasons and URL quirks."""
    mock_ctx = mocks.mctx(facts = {})
    cache = _cache(env, mctx = mock_ctx)

    sdists = {
        # Hashless and yanked.
        "": struct(
            digest = "",
            version = "2.0.0",
            filename = "pkg-2.0.0.tar.gz",
            metadata_url = "",
            metadata_sha256 = "",
            url = "https://pypi.org/files/pkg-2.0.0.tar.gz",
            yanked = "Broken",
        ),
        # Yanked without a reason must stay distinct from not yanked.
        "sha256:empty_reason": struct(
            digest = "sha256:empty_reason",
            version = "1.0.0",
            filename = "pkg-1.0.0.tar.gz",
            metadata_url = "",
            metadata_sha256 = "",
            url = "https://pypi.org/files/pkg-1.0.0.tar.gz",
            yanked = "",
        ),
    }
    whls = {
        # Hashless and the filename differs from the URL basename.
        "": struct(
            digest = "",
            version = "2.0.0",
            filename = "pkg-2.0.0-py3-none-any.whl",
            metadata_url = "",
            metadata_sha256 = "",
            url = "https://pypi.org/files/download/renamed.whl",
            yanked = None,
        ),
        # The query string makes the URL basename differ from the filename.
        "sha256:query": struct(
            digest = "sha256:query",
            version = "1.0.0",
            filename = "pkg-1.0.0-py3-none-any.whl",
            metadata_url = "",
            metadata_sha256 = "",
            url = "https://pypi.org/files/pkg-1.0.0-py3-none-any.whl?token=abc",
            yanked = None,
        ),
    }
    fake_result = struct(
        sdists = sdists,
        whls = whls,
        hashes_by_version = {
            "1.0.0": ["sha256:empty_reason", "sha256:query"],
            "2.0.0": ["", ""],
        },
    )

    key = ("https://{PYPI_INDEX_URL}/pkg/", "https://pypi.org/simple/pkg/", ["1.0.0", "2.0.0"])
    cache.setdefault(key, fake_result)

    cache.expect_facts().contains_exactly({
        "fact_version": "v5",
        "pkg@https://{PYPI_INDEX_URL}": {
            "https://pypi.org/files/": {
                "download/renamed.whl": "|pkg-2.0.0-py3-none-any.whl",
                "pkg-1.0.0-py3-none-any.whl?token=abc": "sha256:query|pkg-1.0.0-py3-none-any.whl",
                "pkg-1.0.0.tar.gz": "sha256:empty_reason||",
                "pkg-2.0.0.tar.gz": "||Broken",
            },
        },
    })

    cache2 = _cache(env, mctx = mocks.mctx(facts = cache.raw_facts()))
    got = cache2.get(key)
    got.sdists().contains_exactly(sdists)
    got.whls().contains_exactly(whls)
    got.hashes_by_version().contains_exactly(fake_result.hashes_by_version)

_tests.append(_test_pypi_cache_facts_round_trip_edge_cases)

def _test_pypi_cache_facts_no_digest_round_trip(env):
    """Verifies that distributions without a digest are kept in the facts."""
    mock_ctx = mocks.mctx(facts = {})
    cache = _cache(env, mctx = mock_ctx)

    fake_result = struct(
        sdists = {},
        whls = {
            "": struct(
                version = "1.0.0",
                filename = "pkg-1.0.0-py3-none-any.whl",
                url = "https://pypi.org/files/pkg-1.0.0-py3-none-any.whl",
                digest = "",
                yanked = None,
            ),
        },
        hashes_by_version = {
            "1.0.0": [""],
        },
    )

    key = ("https://{PYPI_INDEX_URL}/pkg/", "https://pypi.org/simple/pkg/", ["1.0.0"])
    cache.setdefault(key, fake_result)

    cache.expect_facts().contains_exactly({
        "fact_version": "v5",
        "pkg@https://{PYPI_INDEX_URL}": {
            "https://pypi.org/files/": {
                "pkg-1.0.0-py3-none-any.whl": "",
            },
        },
    })

    cache2 = _cache(env, mctx = mocks.mctx(facts = cache.raw_facts()))
    got = cache2.get(key)
    got.whls().contains_exactly({
        "": struct(
            digest = "",
            version = "1.0.0",
            filename = "pkg-1.0.0-py3-none-any.whl",
            metadata_url = "",
            metadata_sha256 = "",
            url = "https://pypi.org/files/pkg-1.0.0-py3-none-any.whl",
            yanked = None,
        ),
    })
    got.sdists().contains_exactly({})
    got.hashes_by_version().contains_exactly({"1.0.0": [""]})

_tests.append(_test_pypi_cache_facts_no_digest_round_trip)

def _test_pypi_cache_ignores_old_facts_version(env):
    """Verifies that facts from a previous storage version are ignored."""
    mock_ctx = mocks.mctx(facts = {
        "dist_hashes": {
            "https://{PYPI_INDEX_URL}": {
                "pkg": {
                    "https://pypi.org/files/pkg-1.0.0-py3-none-any.whl": "sha256:sha_whl",
                },
            },
        },
        "fact_version": "v2",
    })
    cache = _cache(env, mctx = mock_ctx)

    key = ("https://{PYPI_INDEX_URL}/pkg/", "https://pypi.org/simple/pkg/", ["1.0.0"])
    cache.get(key).equals(None)
    cache.expect_facts().contains_exactly({})

_tests.append(_test_pypi_cache_ignores_old_facts_version)

def _test_memory_cache_index_urls(env):
    """Verifies that the cache returns stored values for index_urls."""
    store = {}
    cache = _cache(env, mctx = None, store = store)

    fake_result = {
        "pkg-a": "https://pypi.org/simple/pkg-a/",
        "pkg_b": "https://pypi.org/simple/pkg-b/",
    }

    key = ("https://pypi.org/simple/", "https://pypi.org/simple/", {"pkg-a": None, "pkg_b": None})

    cache.setdefault(key, fake_result)

    got = cache.get(key)
    got.contains_exactly(fake_result)

    key = ("https://pypi.org/simple/", "https://pypi.org/simple/", {"pkg-a": None})
    got = cache.get(key)
    got.contains_exactly({"pkg-a": "https://pypi.org/simple/pkg-a/"})

    key = ("https://pypi.org/simple/", "https://pypi.org/simple/", {"pkg-c": None})
    cache.get(key).equals(None)

_tests.append(_test_memory_cache_index_urls)

def _test_pypi_cache_writes_index_urls_to_facts(env):
    """Verifies that setting index_urls in the cache also populates the facts store."""
    mock_ctx = mocks.mctx(facts = {})
    cache = _cache(env, mctx = mock_ctx)

    fake_result = {
        "pkg-a": "https://pypi.org/simple/pkg-a/",
        "pkg-b": "https://pypi.org/simple/pkg-b/",
    }

    key = ("https://pypi.org/simple/", "https://pypi.org/simple/", {"pkg-a": None})

    cache.setdefault(key, fake_result)

    cache.expect_facts().contains_exactly({
        "fact_version": "v5",
        "pkg-a@https://pypi.org/simple/": "https://pypi.org/simple/pkg-a/",
    })

    key = ("https://pypi.org/simple/", "https://pypi.org/simple/", {"pkg-b": None})
    cache.setdefault(key, fake_result)

    cache.expect_facts().contains_exactly({
        "fact_version": "v5",
        "pkg-a@https://pypi.org/simple/": "https://pypi.org/simple/pkg-a/",
        "pkg-b@https://pypi.org/simple/": "https://pypi.org/simple/pkg-b/",
    })

_tests.append(_test_pypi_cache_writes_index_urls_to_facts)

def _test_pypi_cache_index_and_dist_facts_do_not_collide(env):
    """Verifies that index page and package page facts for the same package coexist."""
    mock_ctx = mocks.mctx(facts = {})
    cache = _cache(env, mctx = mock_ctx)

    index_key = ("https://pypi.org/simple/", "https://pypi.org/simple/", {"pkg": None})
    cache.setdefault(index_key, {"pkg": "https://pypi.org/simple/pkg/"})

    dist = struct(
        digest = "sha256:whl",
        version = "1.0.0",
        filename = "pkg-1.0.0-py3-none-any.whl",
        metadata_url = "",
        metadata_sha256 = "",
        url = "https://pypi.org/files/pkg-1.0.0-py3-none-any.whl",
        yanked = None,
    )
    dist_key = ("https://pypi.org/simple/pkg/", "https://pypi.org/simple/pkg/", ["1.0.0"])
    cache.setdefault(dist_key, struct(
        sdists = {},
        whls = {"sha256:whl": dist},
        hashes_by_version = {"1.0.0": ["sha256:whl"]},
    ))

    cache.expect_facts().contains_exactly({
        "fact_version": "v5",
        "pkg@https://pypi.org/simple": {
            "https://pypi.org/files/": {
                "pkg-1.0.0-py3-none-any.whl": "sha256:whl",
            },
        },
        "pkg@https://pypi.org/simple/": "https://pypi.org/simple/pkg/",
    })

    cache2 = _cache(env, mctx = mocks.mctx(facts = cache.raw_facts()))
    cache2.get(index_key).contains_exactly({"pkg": "https://pypi.org/simple/pkg/"})
    cache2.get(dist_key).whls().contains_exactly({"sha256:whl": dist})

_tests.append(_test_pypi_cache_index_and_dist_facts_do_not_collide)

def _test_pypi_cache_reads_index_urls_from_facts(env):
    """Verifies that reading index_urls from facts works correctly."""
    mock_ctx = mocks.mctx(facts = {
        "fact_version": "v5",
        "pkg-a@https://pypi.org/simple/": "https://pypi.org/simple/pkg-a/",
        "pkg-b@https://pypi.org/simple/": "https://pypi.org/simple/pkg-b/",
    })
    cache = _cache(env, mctx = mock_ctx)

    key = ("https://pypi.org/simple/", "https://pypi.org/simple/", {"pkg-a": None})
    got = cache.get(key)
    got.contains_exactly({"pkg-a": "https://pypi.org/simple/pkg-a/"})

    key = ("https://pypi.org/simple/", "https://pypi.org/simple/", {"pkg-a": None, "pkg-b": None})
    got = cache.get(key)
    got.contains_exactly({
        "pkg-a": "https://pypi.org/simple/pkg-a/",
        "pkg-b": "https://pypi.org/simple/pkg-b/",
    })

    key = ("https://pypi.org/simple/", "https://pypi.org/simple/", {"pkg-c": None})
    cache.get(key).equals(None)

    cache.expect_facts().contains_exactly(mock_ctx.facts)

_tests.append(_test_pypi_cache_reads_index_urls_from_facts)

def _test_pypi_cache_reads_index_urls_from_facts_incomplete(env):
    """Verifies that incomplete index_urls facts returns None (forces fresh download)."""
    mock_ctx = mocks.mctx(facts = {
        "fact_version": "v5",
        "pkg-a@https://pypi.org/simple/": "https://pypi.org/simple/pkg-a/",
    })
    cache = _cache(env, mctx = mock_ctx)

    # Request pkg-a and pkg-b, but facts only have pkg-a
    key = ("https://pypi.org/simple/", "https://pypi.org/simple/", {"pkg-a": None, "pkg-b": None})
    cache.get(key).equals(None)

_tests.append(_test_pypi_cache_reads_index_urls_from_facts_incomplete)

def _test_pypi_cache_reads_index_urls_from_facts_drops_unaccessed(env):
    """Verifies get_facts() drops unaccessed index_urls entries.

    When known_facts has packages that are not requested, they should not
    appear in computed_facts. This ensures stale facts (from packages
    removed from all requirements files) get cleaned up from the lockfile.
    """
    mock_ctx = mocks.mctx(facts = {
        "fact_version": "v5",
        "pkg-a@https://pypi.org/simple/": "https://pypi.org/simple/pkg-a/",
        "pkg-b@https://pypi.org/simple/": "https://pypi.org/simple/pkg-b/",
        "pkg-c@https://pypi.org/simple/": "https://pypi.org/simple/pkg-c/",
    })
    cache = _cache(env, mctx = mock_ctx)

    # Request only a subset of packages; pkg-c is not requested
    key = ("https://pypi.org/simple/", "https://pypi.org/simple/", {"pkg-a": None, "pkg-b": None})
    got = cache.get(key)
    got.contains_exactly({
        "pkg-a": "https://pypi.org/simple/pkg-a/",
        "pkg-b": "https://pypi.org/simple/pkg-b/",
    })

    # get_facts() must only return the requested (accessed) subset; pkg-c is dropped
    cache.expect_facts().contains_exactly({
        "fact_version": "v5",
        "pkg-a@https://pypi.org/simple/": "https://pypi.org/simple/pkg-a/",
        "pkg-b@https://pypi.org/simple/": "https://pypi.org/simple/pkg-b/",
    })

_tests.append(_test_pypi_cache_reads_index_urls_from_facts_drops_unaccessed)

_MACOS_ARM64_CP312 = struct(
    env = {"implementation_name": "cpython", "python_full_version": "3.12.0"},
    whl_abi_tags = ["none", "abi3", "cp312"],
    whl_platform_tags = ["any", "macosx_*_arm64"],
)

def _dist(filename, yanked = None, version = "1.0.0"):
    return struct(
        version = version,
        filename = filename,
        url = "https://pypi.org/files/" + filename,
        digest = "sha256:" + filename,
        yanked = yanked,
    )

def _test_pypi_cache_facts_store_only_selectable_wheels(env):
    """Verifies that the facts skip the wheels that no platform can select."""
    cache = _cache(env, mctx = mocks.mctx(facts = {}), wheel_platforms = [_MACOS_ARM64_CP312])

    dists = [
        _dist("pkg-1.0.0.tar.gz"),
        _dist("pkg-1.0.0-py3-none-any.whl"),
        _dist("pkg-1.0.0-cp312-cp312-macosx_11_0_arm64.whl"),
        _dist("pkg-1.0.0-cp312-cp312-manylinux_2_17_x86_64.whl"),
        _dist("pkg-1.0.0-cp313-cp313-macosx_11_0_arm64.whl"),
    ]
    fake_result = struct(
        sdists = {d.digest: d for d in dists[:1]},
        whls = {d.digest: d for d in dists[1:]},
        hashes_by_version = {"1.0.0": sorted([d.digest for d in dists])},
    )
    key = ("https://{PYPI_INDEX_URL}/pkg/", "https://pypi.org/simple/pkg/", ["1.0.0"])
    cache.setdefault(key, fake_result)

    cache.expect_facts().contains_exactly({
        "fact_version": "v5",
        "pkg@https://{PYPI_INDEX_URL}": {
            "https://pypi.org/files/": {
                "pkg-1.0.0-cp312-cp312-macosx_11_0_arm64.whl": "sha256:pkg-1.0.0-cp312-cp312-macosx_11_0_arm64.whl",
                "pkg-1.0.0-py3-none-any.whl": "sha256:pkg-1.0.0-py3-none-any.whl",
                "pkg-1.0.0.tar.gz": "sha256:pkg-1.0.0.tar.gz",
            },
        },
        "wheel_filter": ["cpython|3.12|none,abi3,cp312|any,macosx_*_arm64"],
    })

_tests.append(_test_pypi_cache_facts_store_only_selectable_wheels)

_LINUX_X86_64_CP313 = struct(
    env = {"implementation_name": "cpython", "python_full_version": "3.13.0"},
    whl_abi_tags = ["none", "abi3", "cp313"],
    whl_platform_tags = ["any", "manylinux_*_x86_64"],
)

def _test_pypi_cache_facts_store_wheels_selectable_by_any_platform(env):
    """Verifies that the facts keep a wheel that any one of the platforms can select."""
    cache = _cache(
        env,
        mctx = mocks.mctx(facts = {}),
        wheel_platforms = [_MACOS_ARM64_CP312, _LINUX_X86_64_CP313],
    )

    dists = [
        _dist("pkg-1.0.0-cp312-cp312-macosx_11_0_arm64.whl"),
        _dist("pkg-1.0.0-cp313-cp313-manylinux_2_17_x86_64.whl"),
        _dist("pkg-1.0.0-cp312-cp312-win_amd64.whl"),
    ]
    fake_result = struct(
        sdists = {},
        whls = {d.digest: d for d in dists},
        hashes_by_version = {"1.0.0": sorted([d.digest for d in dists])},
    )
    key = ("https://{PYPI_INDEX_URL}/pkg/", "https://pypi.org/simple/pkg/", ["1.0.0"])
    cache.setdefault(key, fake_result)

    cache.expect_facts().contains_exactly({
        "fact_version": "v5",
        "pkg@https://{PYPI_INDEX_URL}": {
            "https://pypi.org/files/": {
                "pkg-1.0.0-cp312-cp312-macosx_11_0_arm64.whl": "sha256:pkg-1.0.0-cp312-cp312-macosx_11_0_arm64.whl",
                "pkg-1.0.0-cp313-cp313-manylinux_2_17_x86_64.whl": "sha256:pkg-1.0.0-cp313-cp313-manylinux_2_17_x86_64.whl",
            },
        },
        "wheel_filter": [
            "cpython|3.12|none,abi3,cp312|any,macosx_*_arm64",
            "cpython|3.13|none,abi3,cp313|any,manylinux_*_x86_64",
        ],
    })

_tests.append(_test_pypi_cache_facts_store_wheels_selectable_by_any_platform)

def _test_pypi_cache_facts_filter_yanked_wheels(env):
    """Verifies that a kept yanked wheel keeps its yank reason and a dropped one is gone."""
    cache = _cache(env, mctx = mocks.mctx(facts = {}), wheel_platforms = [_MACOS_ARM64_CP312])

    kept = _dist("pkg-1.0.0-py3-none-any.whl", yanked = "Broken build")
    dropped = _dist("pkg-1.0.0-cp312-cp312-win_amd64.whl", yanked = "Broken build")
    fake_result = struct(
        sdists = {},
        whls = {d.digest: d for d in [kept, dropped]},
        hashes_by_version = {"1.0.0": sorted([kept.digest, dropped.digest])},
    )
    key = ("https://{PYPI_INDEX_URL}/pkg/", "https://pypi.org/simple/pkg/", ["1.0.0"])
    cache.setdefault(key, fake_result)

    cache.expect_facts().contains_exactly({
        "fact_version": "v5",
        "pkg@https://{PYPI_INDEX_URL}": {
            "https://pypi.org/files/": {
                "pkg-1.0.0-py3-none-any.whl": "sha256:pkg-1.0.0-py3-none-any.whl||Broken build",
            },
        },
        "wheel_filter": ["cpython|3.12|none,abi3,cp312|any,macosx_*_arm64"],
    })

    cache2 = _cache(
        env,
        mctx = mocks.mctx(facts = cache.raw_facts()),
        wheel_platforms = [_MACOS_ARM64_CP312],
    )
    got = cache2.get(key)
    got.whls().contains_exactly({
        kept.digest: struct(
            digest = kept.digest,
            version = "1.0.0",
            filename = kept.filename,
            metadata_url = "",
            metadata_sha256 = "",
            url = kept.url,
            yanked = "Broken build",
        ),
    })
    got.hashes_by_version().contains_exactly({"1.0.0": [kept.digest]})

_tests.append(_test_pypi_cache_facts_filter_yanked_wheels)

def _test_pypi_cache_facts_keep_versions_without_selectable_dists(env):
    """Verifies that the facts keep all dists of a version that no platform can select."""
    cache = _cache(env, mctx = mocks.mctx(facts = {}), wheel_platforms = [_MACOS_ARM64_CP312])

    dists = [
        _dist("pkg-1.0.0-cp312-cp312-win_amd64.whl"),
        _dist("pkg-1.0.0-cp312-cp312-win32.whl"),
        _dist("pkg-2.0.0-cp312-cp312-macosx_11_0_arm64.whl", version = "2.0.0"),
        _dist("pkg-2.0.0-cp312-cp312-win_amd64.whl", version = "2.0.0"),
    ]
    fake_result = struct(
        sdists = {},
        whls = {d.digest: d for d in dists},
        hashes_by_version = {
            "1.0.0": sorted([d.digest for d in dists[:2]]),
            "2.0.0": sorted([d.digest for d in dists[2:]]),
        },
    )
    key = ("https://{PYPI_INDEX_URL}/pkg/", "https://pypi.org/simple/pkg/", ["1.0.0", "2.0.0"])
    cache.setdefault(key, fake_result)

    cache.expect_facts().contains_exactly({
        "fact_version": "v5",
        "pkg@https://{PYPI_INDEX_URL}": {
            "https://pypi.org/files/": {
                "pkg-1.0.0-cp312-cp312-win32.whl": "sha256:pkg-1.0.0-cp312-cp312-win32.whl",
                "pkg-1.0.0-cp312-cp312-win_amd64.whl": "sha256:pkg-1.0.0-cp312-cp312-win_amd64.whl",
                "pkg-2.0.0-cp312-cp312-macosx_11_0_arm64.whl": "sha256:pkg-2.0.0-cp312-cp312-macosx_11_0_arm64.whl",
            },
        },
        "wheel_filter": ["cpython|3.12|none,abi3,cp312|any,macosx_*_arm64"],
    })

    # The facts have all of the requested versions, so the next run reads them.
    cache2 = _cache(
        env,
        mctx = mocks.mctx(facts = cache.raw_facts()),
        wheel_platforms = [_MACOS_ARM64_CP312],
    )
    cache2.get(key).hashes_by_version().contains_exactly({
        "1.0.0": sorted([d.digest for d in dists[:2]]),
        "2.0.0": [dists[2].digest],
    })

_tests.append(_test_pypi_cache_facts_keep_versions_without_selectable_dists)

def _test_pypi_cache_facts_filter_wheels_with_the_same_tags(env):
    """Verifies that wheels with the same tags get the same result across packages."""
    cache = _cache(env, mctx = mocks.mctx(facts = {}), wheel_platforms = [_MACOS_ARM64_CP312])

    for pkg in ["pkg", "other"]:
        dists = [
            _dist(pkg + "-1.0.0-cp312-abi3-macosx_11_0_arm64.whl"),
            _dist(pkg + "-2.0.0-cp312-abi3-macosx_11_0_arm64.whl"),
            _dist(pkg + "-1.0.0-cp312-cp312-win_amd64.whl"),
            _dist(pkg + "-2.0.0-cp312-cp312-win_amd64.whl"),
        ]
        fake_result = struct(
            sdists = {},
            whls = {d.digest: d for d in dists},
            hashes_by_version = {"1.0.0": sorted([d.digest for d in dists])},
        )
        key = ("https://{PYPI_INDEX_URL}/" + pkg + "/", "https://pypi.org/simple/" + pkg + "/", ["1.0.0"])
        cache.setdefault(key, fake_result)

    cache.expect_facts().contains_exactly({
        "fact_version": "v5",
        "other@https://{PYPI_INDEX_URL}": {
            "https://pypi.org/files/": {
                "other-1.0.0-cp312-abi3-macosx_11_0_arm64.whl": "sha256:other-1.0.0-cp312-abi3-macosx_11_0_arm64.whl",
                "other-2.0.0-cp312-abi3-macosx_11_0_arm64.whl": "sha256:other-2.0.0-cp312-abi3-macosx_11_0_arm64.whl",
            },
        },
        "pkg@https://{PYPI_INDEX_URL}": {
            "https://pypi.org/files/": {
                "pkg-1.0.0-cp312-abi3-macosx_11_0_arm64.whl": "sha256:pkg-1.0.0-cp312-abi3-macosx_11_0_arm64.whl",
                "pkg-2.0.0-cp312-abi3-macosx_11_0_arm64.whl": "sha256:pkg-2.0.0-cp312-abi3-macosx_11_0_arm64.whl",
            },
        },
        "wheel_filter": ["cpython|3.12|none,abi3,cp312|any,macosx_*_arm64"],
    })

_tests.append(_test_pypi_cache_facts_filter_wheels_with_the_same_tags)

def _test_pypi_cache_reads_facts_only_for_the_same_wheel_filter(env):
    """Verifies that the facts filtered for other platforms are not read."""
    facts = {
        "fact_version": "v5",
        "pkg@https://{PYPI_INDEX_URL}": {
            "https://pypi.org/files/": {
                "pkg-1.0.0-py3-none-any.whl": "sha256:whl",
            },
        },
        "wheel_filter": ["cpython|3.12|none,abi3,cp312|any,macosx_*_arm64"],
    }
    key = ("https://{PYPI_INDEX_URL}/pkg/", "https://pypi.org/simple/pkg/", ["1.0.0"])

    cache = _cache(env, mctx = mocks.mctx(facts = facts), wheel_platforms = [_MACOS_ARM64_CP312])
    got = cache.get(key)
    got.whls().keys().contains_exactly(["sha256:whl"])
    cache.expect_facts().contains_exactly(facts)

    # A new patch version selects the same wheels, so it reads the same facts.
    patch = struct(
        env = {"implementation_name": "cpython", "python_full_version": "3.12.7"},
        whl_abi_tags = _MACOS_ARM64_CP312.whl_abi_tags,
        whl_platform_tags = _MACOS_ARM64_CP312.whl_platform_tags,
    )
    cache = _cache(env, mctx = mocks.mctx(facts = facts), wheel_platforms = [patch])
    cache.get(key).whls().keys().contains_exactly(["sha256:whl"])

    other = struct(
        env = {"implementation_name": "cpython", "python_full_version": "3.13.0"},
        whl_abi_tags = _MACOS_ARM64_CP312.whl_abi_tags,
        whl_platform_tags = _MACOS_ARM64_CP312.whl_platform_tags,
    )
    cache = _cache(env, mctx = mocks.mctx(facts = facts), wheel_platforms = [other])
    cache.get(key).equals(None)

    cache = _cache(env, mctx = mocks.mctx(facts = facts))
    cache.get(key).equals(None)

_tests.append(_test_pypi_cache_reads_facts_only_for_the_same_wheel_filter)

def _test_pypi_cache_facts_store_urls_relative_to_common_directory(env):
    """Verifies that the dist urls are stored relative to their longest common directory."""

    def _facts_for(urls):
        cache = _cache(env, mctx = mocks.mctx(facts = {}))
        dists = {
            "sha256:{}".format(i): struct(
                digest = "sha256:{}".format(i),
                version = "1.0.0",
                filename = "pkg-1.0.0-py3-none-any.whl",
                metadata_url = "",
                metadata_sha256 = "",
                url = url,
                yanked = None,
            )
            for i, url in enumerate(urls)
        }
        key = ("https://{PYPI_INDEX_URL}/pkg/", "https://pypi.org/simple/pkg/", ["1.0.0"])
        cache.setdefault(key, struct(sdists = {}, whls = dists, hashes_by_version = {"1.0.0": sorted(dists)}))
        got = _cache(env, mctx = mocks.mctx(facts = cache.raw_facts())).get(key)
        got.whls().contains_exactly(dists)
        return cache.raw_facts()["pkg@https://{PYPI_INDEX_URL}"]

    # The common prefix ends inside a directory name, so only the full directories are shared.
    env.expect.that_dict(_facts_for([
        "https://files.example.com/packages/ab/pkg-1.0.0-py3-none-any.whl",
        "https://files.example.com/packages/ac/pkg-1.0.0-py3-none-any.whl",
    ])).contains_exactly({
        "https://files.example.com/packages/": {
            "ab/pkg-1.0.0-py3-none-any.whl": "sha256:0",
            "ac/pkg-1.0.0-py3-none-any.whl": "sha256:1",
        },
    })

    # Different hosts share only the scheme.
    env.expect.that_dict(_facts_for([
        "https://a.example.com/pkg-1.0.0-py3-none-any.whl",
        "https://b.example.com/pkg-1.0.0-py3-none-any.whl",
    ])).contains_exactly({
        "https://": {
            "a.example.com/pkg-1.0.0-py3-none-any.whl": "sha256:0",
            "b.example.com/pkg-1.0.0-py3-none-any.whl": "sha256:1",
        },
    })

    # A single url shares its own directory.
    env.expect.that_dict(_facts_for([
        "https://example.com/files/pkg-1.0.0-py3-none-any.whl",
    ])).contains_exactly({
        "https://example.com/files/": {
            "pkg-1.0.0-py3-none-any.whl": "sha256:0",
        },
    })

    env.expect.that_dict(_facts_for([
        "../../packages/ab/cd/pkg-1.0.0-py3-none-any.whl",
    ])).contains_exactly({
        "../../packages/ab/cd/": {
            "pkg-1.0.0-py3-none-any.whl": "sha256:0",
        },
    })

    # The common directory ends before the query string and the fragment.
    env.expect.that_dict(_facts_for([
        "https://example.com/files/pkg-1.0.0-py3-none-any.whl?token=a/b",
        "https://example.com/files/pkg-1.0.0-py3-none-any.whl?token=a/c",
    ])).contains_exactly({
        "https://example.com/files/": {
            "pkg-1.0.0-py3-none-any.whl?token=a/b": "sha256:0|pkg-1.0.0-py3-none-any.whl",
            "pkg-1.0.0-py3-none-any.whl?token=a/c": "sha256:1|pkg-1.0.0-py3-none-any.whl",
        },
    })

    env.expect.that_dict(_facts_for([
        "https://example.com/files/pkg-1.0.0-py3-none-any.whl#a/b",
    ])).contains_exactly({
        "https://example.com/files/": {
            "pkg-1.0.0-py3-none-any.whl#a/b": "sha256:0|pkg-1.0.0-py3-none-any.whl",
        },
    })

    # A url that ends with `/` can be the common directory itself.
    env.expect.that_dict(_facts_for([
        "https://example.com/files/pkg-1.0.0-py3-none-any.whl/",
    ])).contains_exactly({
        "https://example.com/files/pkg-1.0.0-py3-none-any.whl/": {
            "": "sha256:0|pkg-1.0.0-py3-none-any.whl",
        },
    })

    env.expect.that_dict(_facts_for([
        "https://example.com/files/pkg/",
        "https://example.com/files/pkg/pkg-1.0.0-py3-none-any.whl",
    ])).contains_exactly({
        "https://example.com/files/pkg/": {
            "": "sha256:0|pkg-1.0.0-py3-none-any.whl",
            "pkg-1.0.0-py3-none-any.whl": "sha256:1",
        },
    })

    # One url is a prefix of another.
    env.expect.that_dict(_facts_for([
        "https://example.com/files/pkg-1.0.0-py3-none-any.whl",
        "https://example.com/files/pkg-1.0.0-py3-none-any.whl/download",
    ])).contains_exactly({
        "https://example.com/files/": {
            "pkg-1.0.0-py3-none-any.whl": "sha256:0",
            "pkg-1.0.0-py3-none-any.whl/download": "sha256:1|pkg-1.0.0-py3-none-any.whl",
        },
    })

_tests.append(_test_pypi_cache_facts_store_urls_relative_to_common_directory)

def _test_pypi_cache_ignores_malformed_dist_facts(env):
    """Verifies that a dist fact that does not group its entries by directory is treated as absent."""
    key = ("https://{PYPI_INDEX_URL}/pkg/", "https://pypi.org/simple/pkg/", ["1.0.0"])
    for fact in [
        {"pkg-1.0.0-py3-none-any.whl": "sha256:sha_whl"},
        {"": "https://pypi.org/files/", "pkg-1.0.0-py3-none-any.whl": "sha256:sha_whl"},
        {"https://pypi.org/files/": None},
        "https://pypi.org/files/pkg-1.0.0-py3-none-any.whl",
    ]:
        cache = _cache(env, mctx = mocks.mctx(facts = {
            "fact_version": "v5",
            "pkg@https://{PYPI_INDEX_URL}": fact,
        }))
        cache.get(key).equals(None)
        cache.expect_facts().contains_exactly({})

_tests.append(_test_pypi_cache_ignores_malformed_dist_facts)

def _test_pypi_cache_ignores_v4_facts(env):
    """Verifies that the v4 facts, which store the full dist urls, are ignored."""
    mock_ctx = mocks.mctx(facts = {
        "fact_version": "v4",
        "pkg@https://{PYPI_INDEX_URL}": {
            "https://pypi.org/files/pkg-1.0.0-py3-none-any.whl": "sha256:sha_whl",
        },
    })
    cache = _cache(env, mctx = mock_ctx)

    key = ("https://{PYPI_INDEX_URL}/pkg/", "https://pypi.org/simple/pkg/", ["1.0.0"])
    cache.get(key).equals(None)
    cache.expect_facts().contains_exactly({})

_tests.append(_test_pypi_cache_ignores_v4_facts)

def pypi_cache_test_suite(name):
    test_suite(
        name = name,
        basic_tests = _tests,
    )
