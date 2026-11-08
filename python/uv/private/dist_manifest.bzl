"""Resolve `uv` release artifact URLs and checksums from a `dist-manifest.json`.

`uv` releases are packaged with cargo-dist, which publishes a
`dist-manifest.json` next to the release artifacts. This file is shared by the
`uv` module extension (bzlmod) and the {obj}`uv_toolchains_manifest` repository
rule (WORKSPACE), so it must not load either of them.
"""

load("//python/private:auth.bzl", "get_auth")

# The manifest file name cargo-dist publishes with each release.
DEFAULT_MANIFEST_FILENAME = "dist-manifest.json"

# See https://github.com/astral-sh/setup-uv/pull/809.
GITHUB_RELEASES_PREFIX = "https://github.com/astral-sh/uv/releases/download/"
ASTRAL_MIRROR_PREFIX = "https://releases.astral.sh/github/uv/releases/download/"

def _overlap(first_collection, second_collection):
    for x in first_collection:
        if x in second_collection:
            return True

    return False

def dist_manifest_resolver(mrctx, *, get_auth = get_auth):
    """Return a `resolve_sources` callback that reads the release manifest.

    Args:
        mrctx: {type}`module_ctx | repository_ctx` the context used to download
            and read the manifests.
        get_auth: the auth function to use.

    Returns:
        {type}`callable` accepting `version`, `config` and `auth` keyword
        arguments, as `define_toolchains` expects, that returns the download
        `urls` and `sha256` keyed by platform for the version.
    """

    def _resolve(*, version, config, auth):
        return get_tool_urls_from_dist_manifest(
            mrctx,
            base_url = "{base_url}/{version}".format(
                version = version,
                base_url = config["base_url"],
            ),
            manifest_filename = config["manifest_filename"],
            platforms = sorted(config["platforms"]),
            get_auth = get_auth,
            **auth
        )

    return _resolve

def get_tool_urls_from_dist_manifest(
        mrctx,
        *,
        base_url,
        manifest_filename,
        platforms,
        get_auth = get_auth,
        **auth_attrs):
    """Download the results about remote tool sources.

    This relies on the tools using the cargo packaging to infer the actual
    sha256 values for each binary.

    Example manifest url: https://github.com/astral-sh/uv/releases/download/0.6.5/dist-manifest.json

    The example format is as below

        dist_version	"0.28.0"
        announcement_tag	"0.6.5"
        announcement_tag_is_implicit	false
        announcement_is_prerelease	false
        announcement_title	"0.6.5"
        announcement_changelog	"text"
        announcement_github_body	"MD text"
        releases	[
            {
                app_name	"uv"
                app_version	"0.6.5"
                env
                    install_dir_env_var	"UV_INSTALL_DIR"
                    unmanaged_dir_env_var	"UV_UNMANAGED_INSTALL"
                    disable_update_env_var	"UV_DISABLE_UPDATE"
                    no_modify_path_env_var	"UV_NO_MODIFY_PATH"
                    github_base_url_env_var	"UV_INSTALLER_GITHUB_BASE_URL"
                    ghe_base_url_env_var	"UV_INSTALLER_GHE_BASE_URL"
                display_name	"uv"
                display	true
            artifacts	[
                "source.tar.gz"
                "source.tar.gz.sha256"
                "uv-installer.sh"
                "uv-installer.ps1"
                "sha256.sum"
                "uv-aarch64-apple-darwin.tar.gz"
                "uv-aarch64-apple-darwin.tar.gz.sha256"
                "...
            ]
            hosting
                order
                0	"simple"
                1	"github"
                github
                    artifact_base_url	"https://github.com"
                    artifact_download_path	"/astral-sh/uv/releases/download/0.11.2"
                    owner	"astral-sh"
                    repo	"uv"
                simple
                    download_url	"https://releases.astral.sh/github/uv/releases/download/0.11.2"
        artifacts
            uv-aarch64-apple-darwin.tar.gz
                name	"uv-aarch64-apple-darwin.tar.gz"
                kind	"executable-zip"
                target_triples	[
                    "aarch64-apple-darwin"
                assets	[
                    {
                        id	"uv-aarch64-apple-darwin-exe-uv"
                        name	"uv"
                        path	"uv"
                        kind	"executable"
                    },
                    {
                        id	"uv-aarch64-apple-darwin-exe-uvx"
                        name	"uvx"
                        path	"uvx"
                        kind	"executable"
                    }
                ]
                checksum	"uv-aarch64-apple-darwin.tar.gz.sha256"
                checksums
                    sha256	"0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
            uv-aarch64-apple-darwin.tar.gz.sha256
                name	"uv-aarch64-apple-darwin.tar.gz.sha256"
                kind	"checksum"
                target_triples	[
                    "aarch64-apple-darwin"
                ]

    Args:
        mrctx: {type}`module_ctx | repository_ctx` the context used to download
            and read files.
        base_url: {type}`str` the URL of the release directory containing the
            manifest and the artifacts, e.g.
            `https://github.com/astral-sh/uv/releases/download/0.6.5`.
        manifest_filename: {type}`str` the manifest file name in `base_url`.
        platforms: {type}`list[str] | None` the platform target triples to
            resolve, or `None` to resolve every platform in the manifest.
        get_auth: the auth function to use.
        **auth_attrs: `netrc` and `auth_patterns` values passed to `get_auth`.

    Returns:
        {type}`dict[str, struct]` the download `urls` and `sha256` keyed by
        platform. Platforms without an artifact in the manifest are absent.
    """
    auth_attr = struct(**auth_attrs)
    dist_manifest = mrctx.path(manifest_filename)
    urls = [base_url + "/" + manifest_filename]
    result = mrctx.download(
        url = urls,
        output = dist_manifest,
        auth = get_auth(mrctx, urls, ctx_attr = auth_attr),
    )
    if not result.success:
        fail(result)
    dist_manifest = json.decode(mrctx.read(dist_manifest))

    # Use the simple download_url from the manifest, when available.
    dist_base_url = (
        dist_manifest
            .get("releases", [{}])[0]
            .get("hosting", {})
            .get("simple", {})
            .get("download_url", base_url)
    )

    # For official releases, add the astral mirror to improve availability.
    # See https://github.com/astral-sh/setup-uv/pull/809.
    if dist_base_url.startswith(GITHUB_RELEASES_PREFIX):
        astral_base_url = ASTRAL_MIRROR_PREFIX + dist_base_url[len(GITHUB_RELEASES_PREFIX):]
        base_urls = [
            astral_base_url,
            dist_base_url,
        ]
    else:
        base_urls = [dist_base_url]

    artifacts = dist_manifest["artifacts"]
    tool_sources = {}
    downloads = {}
    for fname, artifact in artifacts.items():
        if artifact.get("kind") != "executable-zip":
            continue
        target_triples = artifact["target_triples"]
        if platforms != None and not _overlap(target_triples, platforms):
            # We are not interested in this platform, so skip.
            continue

        # Releases of uv >= 0.11.0 have the sha256 directly inline.
        sha256 = artifact.get("checksums", {}).get("sha256", "")
        if len(sha256) > 0:
            for platform in target_triples:
                tool_sources[platform] = struct(
                    urls = [
                        "{}/{}".format(base, fname)
                        for base in base_urls
                    ],
                    sha256 = sha256,
                )
            continue

        # For uv < 0.11.0, we'll need to fetch the individual sha256 files.
        checksum = artifacts[artifact["checksum"]]
        checksum_fname = checksum["name"]
        checksum_path = mrctx.path(checksum_fname)
        urls = ["{}/{}".format(dist_base_url, checksum_fname)]
        downloads[checksum_path] = struct(
            download = mrctx.download(
                url = urls,
                output = checksum_path,
                block = False,
                auth = get_auth(mrctx, urls, ctx_attr = auth_attr),
            ),
            archive_fname = fname,
            platforms = target_triples,
        )

    for checksum_path, download in downloads.items():
        result = download.download.wait()
        if not result.success:
            fail(result)

        archive_fname = download.archive_fname

        sha256, _, checksummed_fname = mrctx.read(checksum_path).partition(" ")
        checksummed_fname = checksummed_fname.strip(" *\n")
        if checksummed_fname and archive_fname != checksummed_fname:
            fail("The checksum is for a different file, expected '{}' but got '{}'".format(
                archive_fname,
                checksummed_fname,
            ))

        for platform in download.platforms:
            tool_sources[platform] = struct(
                urls = [
                    "{}/{}".format(base, archive_fname)
                    for base in base_urls
                ],
                sha256 = sha256,
            )

    return tool_sources
