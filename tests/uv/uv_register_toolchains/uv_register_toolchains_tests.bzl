"""Tests for the WORKSPACE `uv_register_toolchains` macro."""

load("@rules_testing//lib:test_suite.bzl", "test_suite")
load("//python/uv/private:toolchain_types.bzl", "UV_TOOLCHAIN_TYPE")  # buildifier: disable=bzl-visibility
load("//python/uv/private:uv_defaults.bzl", "DEFAULT_PLATFORMS", "DEFAULT_VERSION")  # buildifier: disable=bzl-visibility
load("//python/uv/private:uv_register_toolchains.bzl", "testing")  # buildifier: disable=bzl-visibility

_tests = []

def _manifest(version, platforms):
    """The `dist_manifest.bzl` data of one version with archives for `platforms`."""
    return {
        platform: {
            "sha256": "sha256-of-" + platform,
            "urls": ["https://mirror.example.com/{}/uv-{}.tar.gz".format(version, platform)],
        }
        for platform in platforms
    }

def _manifests(versions):
    """The `dist_manifest.bzl` data of `(version, platforms)` pairs, in that order.

    A list rather than a dict literal, because buildifier sorts the keys of
    dict literals and the order of the manifests is significant.
    """
    return {version: _manifest(version, platforms) for version, platforms in versions}

def _register(**kwargs):
    """Call `uv_register_toolchains` and record what it would create.

    Args:
        **kwargs: overrides of the `uv_register_toolchains` arguments.

    Returns:
        {type}`struct` with the recorded `uv_repository` calls as
        `repositories`, the hub repository call as `hub` and the patterns
        passed to `register_toolchains` as `registered`.
    """
    repositories = []
    hubs = []
    registered = []
    defaults = dict(
        name = "uv",
        manifests = None,
        version = None,
        configure = None,
        netrc = None,
        auth_patterns = None,
        uv_repository = lambda **kwargs: repositories.append(kwargs),
        hub_repo = lambda **kwargs: hubs.append(kwargs),
        register_toolchains = lambda pattern: registered.append(pattern),
    )
    testing.uv_register_toolchains(**(defaults | kwargs))
    return struct(
        repositories = repositories,
        hub = hubs[0],
        registered = registered,
    )

def _test_defaults(env):
    # The manifest has an archive for a platform that is not a default one,
    # and lacks the other default platforms.
    result = _register(
        manifests = {
            DEFAULT_VERSION: _manifest(DEFAULT_VERSION, [
                "aarch64-apple-darwin",
                "aarch64-unknown-linux-musl",
                "x86_64-unknown-linux-gnu",
            ]),
        },
    )

    # Only the default platforms in the manifest get toolchains, in platform
    # order, with the archives the manifest advertises.
    env.expect.that_collection(result.repositories).contains_exactly([
        {
            "name": "uv_0_13_5_aarch64_apple_darwin",
            "platform": "aarch64-apple-darwin",
            "sha256": "sha256-of-aarch64-apple-darwin",
            "urls": ["https://mirror.example.com/0.13.5/uv-aarch64-apple-darwin.tar.gz"],
            "version": "0.13.5",
        },
        {
            "name": "uv_0_13_5_x86_64_unknown_linux_gnu",
            "platform": "x86_64-unknown-linux-gnu",
            "sha256": "sha256-of-x86_64-unknown-linux-gnu",
            "urls": ["https://mirror.example.com/0.13.5/uv-x86_64-unknown-linux-gnu.tar.gz"],
            "version": "0.13.5",
        },
    ]).in_order()
    env.expect.that_dict(result.hub).contains_exactly({
        "name": "uv",
        "toolchain_compatible_with": {
            "0_13_5_aarch64_apple_darwin": DEFAULT_PLATFORMS["aarch64-apple-darwin"].compatible_with,
            "0_13_5_x86_64_unknown_linux_gnu": DEFAULT_PLATFORMS["x86_64-unknown-linux-gnu"].compatible_with,
        },
        "toolchain_implementations": {
            "0_13_5_aarch64_apple_darwin": "@uv_0_13_5_aarch64_apple_darwin//:uv_toolchain",
            "0_13_5_x86_64_unknown_linux_gnu": "@uv_0_13_5_x86_64_unknown_linux_gnu//:uv_toolchain",
        },
        "toolchain_names": [
            "0_13_5_aarch64_apple_darwin",
            "0_13_5_x86_64_unknown_linux_gnu",
        ],
        "toolchain_target_settings": {},
        "toolchain_type": str(UV_TOOLCHAIN_TYPE),
    })
    env.expect.that_collection(result.registered).contains_exactly(["@uv//:all"])

_tests.append(_test_defaults)

def _test_every_manifest_version_by_default(env):
    # One hub holds the toolchains of all the fetched versions, in manifest
    # order.
    result = _register(
        name = "my_uv",
        manifests = _manifests([
            ("0.6.5", ["x86_64-unknown-linux-gnu"]),
            ("0.13.5", ["aarch64-apple-darwin", "x86_64-unknown-linux-gnu"]),
        ]),
    )

    env.expect.that_collection([r["name"] for r in result.repositories]).contains_exactly([
        "my_uv_0_6_5_x86_64_unknown_linux_gnu",
        "my_uv_0_13_5_aarch64_apple_darwin",
        "my_uv_0_13_5_x86_64_unknown_linux_gnu",
    ]).in_order()
    env.expect.that_collection(result.hub["toolchain_names"]).contains_exactly([
        "0_6_5_x86_64_unknown_linux_gnu",
        "0_13_5_aarch64_apple_darwin",
        "0_13_5_x86_64_unknown_linux_gnu",
    ]).in_order()
    env.expect.that_collection(result.registered).contains_exactly(["@my_uv//:all"])

_tests.append(_test_every_manifest_version_by_default)

def _test_version_defaults_to_first_manifest(env):
    result = _register(
        manifests = _manifests([
            ("0.6.5", ["x86_64-unknown-linux-gnu"]),
            ("0.13.5", ["x86_64-unknown-linux-gnu"]),
        ]),
        configure = [
            # Applies to 0.6.5, the first manifest version.
            {"platform": "x86_64-unknown-linux-gnu", "target_settings": ["@//:use_old_uv"]},
            {"version": "0.13.5"},
        ],
    )

    env.expect.that_collection(result.hub["toolchain_names"]).contains_exactly([
        "0_6_5_x86_64_unknown_linux_gnu",
        "0_13_5_x86_64_unknown_linux_gnu",
    ]).in_order()
    env.expect.that_dict(result.hub["toolchain_target_settings"]).contains_exactly({
        "0_6_5_x86_64_unknown_linux_gnu": ["@//:use_old_uv"],
    })

_tests.append(_test_version_defaults_to_first_manifest)

def _test_configure(env):
    result = _register(
        manifests = {
            DEFAULT_VERSION: _manifest(DEFAULT_VERSION, [
                "aarch64-apple-darwin",
                "aarch64-unknown-linux-musl",
                "x86_64-unknown-linux-gnu",
            ]),
        },
        netrc = "/home/user/.netrc",
        configure = [
            # Removes a default platform that the manifest has.
            {"platform": "aarch64-apple-darwin"},
            # Adds a platform the manifest has; labels are passed on as
            # strings.
            {
                "compatible_with": [Label("@platforms//os:linux"), "@platforms//cpu:aarch64"],
                "platform": "aarch64-unknown-linux-musl",
                "target_settings": [Label("//:is_musl")],
            },
            # A version without a manifest, with explicit archives: only the
            # listed platform, with its own auth.
            {
                "auth_patterns": {"mirror.example.com": "Bearer <password>"},
                "platform": "x86_64-apple-darwin",
                "sha256": "deadbeef",
                "urls": ["https://mirror.example.com/uv-0.6.5-x86_64-apple-darwin.tar.gz"],
                "version": "0.6.5",
            },
        ],
    )

    # The default auth applies to every version, like `uv.default`; added
    # platforms come after the default ones.
    env.expect.that_collection(result.repositories).contains_exactly([
        {
            "name": "uv_0_13_5_x86_64_unknown_linux_gnu",
            "netrc": "/home/user/.netrc",
            "platform": "x86_64-unknown-linux-gnu",
            "sha256": "sha256-of-x86_64-unknown-linux-gnu",
            "urls": ["https://mirror.example.com/0.13.5/uv-x86_64-unknown-linux-gnu.tar.gz"],
            "version": "0.13.5",
        },
        {
            "name": "uv_0_13_5_aarch64_unknown_linux_musl",
            "netrc": "/home/user/.netrc",
            "platform": "aarch64-unknown-linux-musl",
            "sha256": "sha256-of-aarch64-unknown-linux-musl",
            "urls": ["https://mirror.example.com/0.13.5/uv-aarch64-unknown-linux-musl.tar.gz"],
            "version": "0.13.5",
        },
        {
            "auth_patterns": {"mirror.example.com": "Bearer <password>"},
            "name": "uv_0_6_5_x86_64_apple_darwin",
            "netrc": "/home/user/.netrc",
            "platform": "x86_64-apple-darwin",
            "sha256": "deadbeef",
            "urls": ["https://mirror.example.com/uv-0.6.5-x86_64-apple-darwin.tar.gz"],
            "version": "0.6.5",
        },
    ]).in_order()
    env.expect.that_dict(result.hub["toolchain_compatible_with"]).contains_exactly({
        "0_13_5_aarch64_unknown_linux_musl": [
            str(Label("@platforms//os:linux")),
            "@platforms//cpu:aarch64",
        ],
        "0_13_5_x86_64_unknown_linux_gnu": DEFAULT_PLATFORMS["x86_64-unknown-linux-gnu"].compatible_with,
        "0_6_5_x86_64_apple_darwin": DEFAULT_PLATFORMS["x86_64-apple-darwin"].compatible_with,
    })
    env.expect.that_dict(result.hub["toolchain_target_settings"]).contains_exactly({
        "0_13_5_aarch64_unknown_linux_musl": [str(Label("//:is_musl"))],
    })

_tests.append(_test_configure)

def _test_without_manifests(env):
    result = _register(
        configure = [
            {
                "platform": "x86_64-unknown-linux-gnu",
                "sha256": "deadbeef",
                "urls": ["https://mirror.example.com/uv.tar.gz"],
            },
        ],
    )

    env.expect.that_collection(result.repositories).contains_exactly([
        {
            "name": "uv_0_13_5_x86_64_unknown_linux_gnu",
            "platform": "x86_64-unknown-linux-gnu",
            "sha256": "deadbeef",
            "urls": ["https://mirror.example.com/uv.tar.gz"],
            "version": DEFAULT_VERSION,
        },
    ])
    env.expect.that_collection(result.hub["toolchain_names"]).contains_exactly([
        "0_13_5_x86_64_unknown_linux_gnu",
    ])

_tests.append(_test_without_manifests)

def uv_register_toolchains_test_suite(name):
    """Create the test suite.

    Args:
        name: the name of the test suite
    """
    test_suite(
        name = name,
        basic_tests = _tests,
    )
