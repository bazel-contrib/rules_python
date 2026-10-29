"""Tests for the WORKSPACE `uv_toolchains_manifest` repository rule."""

load("@rules_testing//lib:test_suite.bzl", "test_suite")
load("//python/uv/private:dist_manifest.bzl", "DEFAULT_MANIFEST_FILENAME")  # buildifier: disable=bzl-visibility
load("//python/uv/private:uv_defaults.bzl", "DEFAULT_BASE_URL", "DEFAULT_VERSION")  # buildifier: disable=bzl-visibility
load("//python/uv/private:uv_toolchains_manifest.bzl", "testing")  # buildifier: disable=bzl-visibility
load("//tests/support/mocks:mocks.bzl", "mocks")

_tests = []

# The platforms the fake release manifest has archives for.
_RELEASED = ["aarch64-apple-darwin", "x86_64-unknown-linux-gnu"]

def _manifest():
    """A fake cargo-dist manifest with inline checksums (uv >= 0.11)."""
    return json.encode({
        "artifacts": {
            "uv-{}.tar.gz".format(platform): {
                "checksums": {"sha256": "sha256-of-" + platform},
                "kind": "executable-zip",
                "target_triples": [platform],
            }
            for platform in _RELEASED
        },
        "releases": [{
            "hosting": {
                "simple": {
                    "download_url": "https://mirror.example.com/archives",
                },
            },
        }],
    })

def _generate(*, manifest_urls, **kwargs):
    """Call `generate_dist_manifest_bzl` with a mocked repository context.

    Args:
        manifest_urls: {type}`list[str]` the manifest URLs the mock serves;
            any other download fails.
        **kwargs: overrides of the `generate_dist_manifest_bzl` arguments.

    Returns:
        {type}`struct` with the generated `content` and the `downloads` that
        were requested.
    """
    downloads = []

    def _download(rctx, url, *_):
        _ = rctx  # @unused
        downloads.append(url)
        return struct(success = True, wait = lambda: struct(success = True))

    rctx = mocks.rctx(
        mock_downloads = {url: _download for url in manifest_urls},
        mock_files = {
            kwargs.get("manifest_filename", DEFAULT_MANIFEST_FILENAME): _manifest(),
        },
    )
    defaults = dict(
        name = "uv_manifest",
        versions = [DEFAULT_VERSION],
        base_url = DEFAULT_BASE_URL,
        manifest_filename = DEFAULT_MANIFEST_FILENAME,
        netrc = "",
        auth_patterns = {},
        get_auth = lambda *_, **__: None,
    )
    content = testing.generate_dist_manifest_bzl(rctx, **(defaults | kwargs))
    return struct(
        content = content,
        downloads = downloads,
    )

def _test_defaults(env):
    manifest_url = "{}/{}/{}".format(DEFAULT_BASE_URL, DEFAULT_VERSION, DEFAULT_MANIFEST_FILENAME)
    result = _generate(manifest_urls = [manifest_url])

    env.expect.that_collection(result.downloads).contains_exactly([manifest_url])

    # Every archive of the manifest is written out, with the download URL the
    # manifest advertises, and `uv_register_toolchains` is bound to them.
    env.expect.that_str(result.content).contains("""\
DIST_MANIFESTS = {
    "0.13.5": {
        "aarch64-apple-darwin": {
            "sha256": "sha256-of-aarch64-apple-darwin",
            "urls": [
                "https://mirror.example.com/archives/uv-aarch64-apple-darwin.tar.gz"
            ]
        },
        "x86_64-unknown-linux-gnu": {
            "sha256": "sha256-of-x86_64-unknown-linux-gnu",
            "urls": [
                "https://mirror.example.com/archives/uv-x86_64-unknown-linux-gnu.tar.gz"
            ]
        }
    }
}
""")
    env.expect.that_str(result.content).contains(
        'load("@rules_python//python/uv:repositories.bzl", _uv_register_toolchains = "uv_register_toolchains")',
    )
    env.expect.that_str(result.content).contains("def uv_register_toolchains(**kwargs):")
    env.expect.that_str(result.content).contains(
        'kwargs["manifests"] = DIST_MANIFESTS | (kwargs.get("manifests") or {})',
    )
    env.expect.that_str(result.content).contains('uv_toolchains_manifest(name = "uv_manifest")')

_tests.append(_test_defaults)

def _test_versions_from_a_mirror(env):
    manifest_urls = [
        "https://mirror.example.com/uv/{}/{}".format(version, "manifest.json")
        for version in ["0.13.5", "0.6.5"]
    ]
    result = _generate(
        manifest_urls = manifest_urls,
        versions = ["0.13.5", "0.6.5"],
        base_url = "https://mirror.example.com/uv",
        manifest_filename = "manifest.json",
    )

    # One manifest per version, in `versions` order.
    env.expect.that_collection(result.downloads).contains_exactly(manifest_urls).in_order()
    env.expect.that_str(result.content).contains('\n    "0.13.5": {\n')
    env.expect.that_str(result.content).contains('\n    "0.6.5": {\n')
    env.expect.that_bool(
        result.content.find('"0.13.5"') < result.content.find('"0.6.5"'),
    ).equals(True)

_tests.append(_test_versions_from_a_mirror)

def uv_toolchains_manifest_test_suite(name):
    """Create the test suite.

    Args:
        name: the name of the test suite
    """
    test_suite(
        name = name,
        basic_tests = _tests,
    )
