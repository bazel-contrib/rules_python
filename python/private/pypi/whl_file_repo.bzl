"""Store an original or patched wheel separately from its extracted files."""

load("//python/private:auth.bzl", "AUTH_ATTRS", "get_auth")
load("//python/private:repo_utils.bzl", "REPO_DEBUG_ENV_VAR", "repo_utils")
load(":attrs.bzl", "ATTRS")
load(":patch_whl.bzl", "patch_whl")
load(":urllib.bzl", "urllib")

def download_whl(rctx, *, logger):
    """Download a wheel and return its path, preserving index authentication.

    Args:
        rctx: The repository context.
        logger: The repository logger.

    Returns:
        The path of the downloaded wheel.
    """
    filename = rctx.attr.filename
    if not filename.endswith(".whl"):
        fail("Only wheels are supported")
    urls = [
        urllib.absolute_url(
            rctx.attr.index_url,
            url,
            envsubst = rctx.attr.envsubst,
            getenv = rctx.getenv,
        )
        for url in rctx.attr.urls
    ]
    result = rctx.download(
        url = urls,
        output = filename,
        sha256 = rctx.attr.sha256,
        integrity = rctx.attr.integrity if not rctx.attr.sha256 else "",
        auth = get_auth(rctx, urls),
    )
    if not rctx.attr.sha256 and not rctx.attr.integrity:
        logger.warn("Please update the requirement line to include the hash:\n{} \\\n    --hash=sha256:{}".format(
            rctx.attr.requirement,
            result.sha256,
        ))
    if not result.success:
        fail("could not download the '{}' from {}:\n{}".format(filename, urls, result))
    return rctx.path(filename)

whl_file_repo_attrs = {
    "envsubst": ATTRS["envsubst"],
    "filename": attr.string(doc = "The filename of the downloaded wheel."),
    "index_url": attr.string(doc = "The index URL used to resolve relative wheel URLs."),
    "integrity": attr.string(doc = "The expected SRI checksum, used when sha256 is unset."),
    "patches": attr.label_keyed_string_dict(doc = "Patch labels mapped to their strip levels."),
    "requirement": attr.string(doc = "The requirement used in download diagnostics."),
    "sha256": attr.string(doc = "The expected SHA256 checksum."),
    "urls": attr.string_list(doc = "The wheel download URLs."),
    "whl_file": attr.label(doc = "A caller-owned wheel to use instead of downloading."),
} | AUTH_ATTRS

def _whl_file_repo_impl(rctx):
    if rctx.attr.whl_file:
        rctx.watch(rctx.attr.whl_file)
        whl_path = rctx.path(rctx.attr.whl_file)

        # patch_whl deletes its input before repacking. Keep caller-owned
        # wheels intact by giving it a repository-local symlink.
        rctx.symlink(whl_path, whl_path.basename)
        whl_path = rctx.path(whl_path.basename)
    else:
        whl_path = download_whl(rctx, logger = repo_utils.logger(rctx))
    if rctx.attr.patches:
        whl_path = patch_whl(
            rctx,
            whl_path = whl_path,
            patches = {patch: int(strip) for patch, strip in rctx.attr.patches.items()},
        )

        # Patching temporarily unpacks the input. Retain only the replacement
        # wheel; the installation is extracted in the consuming repository.
        for path in rctx.path(".").readdir():
            if path.basename != whl_path.basename:
                rctx.delete(path)
    rctx.file("BUILD.bazel", "exports_files([{}])\n".format(repr(whl_path.basename)))
    if hasattr(rctx, "repo_metadata"):
        return rctx.repo_metadata(reproducible = True)
    return None

whl_file_repo = repository_rule(
    implementation = _whl_file_repo_impl,
    attrs = whl_file_repo_attrs | {
        "_rule_name": attr.string(default = "whl_file_repo"),
    },
    environ = [REPO_DEBUG_ENV_VAR],
)
