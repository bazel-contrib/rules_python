""

load("//python/private:auth.bzl", "AUTH_ATTRS", "get_auth")
load("//python/private:repo_utils.bzl", "REPO_DEBUG_ENV_VAR", "repo_utils")
load(":attrs.bzl", "ATTRS")
load(":patch_and_extract_whl.bzl", "patch_and_extract_whl")
load(":urllib.bzl", "urllib")
load(":whl_deps_repo.bzl", "whl_deps_attrs")

def _whl_archive_impl(rctx):
    logger = repo_utils.logger(rctx)

    whl_path = None
    if rctx.attr.whl_file:
        rctx.watch(rctx.attr.whl_file)
        whl_path = rctx.path(rctx.attr.whl_file)

        # Simulate the behaviour where the whl is present in the current directory.
        rctx.symlink(whl_path, whl_path.basename)
        whl_path = rctx.path(whl_path.basename)
    elif rctx.attr.urls and rctx.attr.filename:
        filename = rctx.attr.filename
        urls = rctx.attr.urls
        urls = [
            urllib.absolute_url(
                rctx.attr.index_url,
                url,
                envsubst = rctx.attr.envsubst,
                getenv = rctx.getenv,
            )
            for url in urls
        ]
        result = rctx.download(
            url = urls,
            output = filename,
            sha256 = rctx.attr.sha256,
            integrity = rctx.attr.integrity if not rctx.attr.sha256 else "",
            auth = get_auth(rctx, urls),
        )
        if not rctx.attr.sha256 and not rctx.attr.integrity:
            # this is only seen when there is a direct URL reference without a hash
            logger.warn("Please update the requirement line to include the hash:\n{} \\\n    --hash=sha256:{}".format(
                rctx.attr.requirement,
                result.sha256,
            ))

        if not result.success:
            fail("could not download the '{}' from {}:\n{}".format(filename, urls, result))

        if filename.endswith(".whl"):
            whl_path = rctx.path(filename)
        else:
            fail("Only wheels are supported")
    else:
        fail("Either 'whl_file' or 'urls' and 'filename' needs to be specified")

    return patch_and_extract_whl(rctx, whl_path = whl_path, logger = logger)

whl_archive_attrs = whl_deps_attrs | {
    "annotation": attr.label(
        doc = (
            "Optional json encoded file containing annotation to apply to the extracted wheel. " +
            "See `package_annotation`"
        ),
        allow_files = True,
    ),
    "filename": attr.string(
        doc = "Download the whl file to this filename. Only used when the `urls` is passed. If not specified, will be auto-detected from the `urls`.",
    ),
    "index_url": attr.string(
        doc = "The index_url that the package will be downloaded from.",
    ),
    "integrity": attr.string(
        doc = """\
The expected checksum of the downloaded whl in Subresource Integrity format
(e.g. `sha256-...` or `sha512-...`). Only used when `urls` is passed. If
`sha256` is also set, it takes precedence over this attribute.

:::{versionadded} 2.3.0
:::
""",
    ),
    "sha256": attr.string(
        doc = "The sha256 of the downloaded whl. Only used when the `urls` is passed.",
    ),
    "urls": attr.string_list(
        doc = """\
The list of urls of the whl to be downloaded using bazel downloader. Using this
attr makes `extra_pip_args` and `download_only` ignored.""",
    ),
    # attributes only relevant to this rule and not reusable outside
    "whl_file": attr.label(
        doc = "The whl file that should be used instead of downloading or building the whl.",
    ),
    "whl_patches": attr.label_keyed_string_dict(
        doc = """
A label-keyed-string dict with patch files as keys and json-strings as values.

The keys are labels to the patch file to apply.

The values describe what to apply the patch to and how to apply it.
It is encoded as `json.encode(struct([whls], patch_strip])`,
where `whls` is a `list[str`] of wheel filenames, and `patch_strip`
is a number.

So it will look something like this:
```
"//path/to/package:my.patch": json.encode(struct(
    whls = ["something-2.7.1-py3-none-any.whl"],
    patch_strip = 1,
)),
```
The patch is applied within the scope of the .whl file.
I.e. you should create the patch from the same place you unziped the wheel.


This is to maintain flexibility and correct bzlmod extension interface until we have a better
way to define whl_library and move whl patching to a separate place. INTERNAL USE ONLY.""",
    ),
} | {
    k: ATTRS[k]
    for k in [
        # legacy parameters that are global to the entire hub.
        "enable_implicit_namespace_pkgs",
        "envsubst",
        "pip_data_exclude",
    ]
} | AUTH_ATTRS

whl_archive = repository_rule(
    attrs = whl_archive_attrs | {
        "_rule_name": attr.string(default = "whl_archive"),
    },
    doc = """
Download and extracts a single wheel based into a bazel repo based on the requirement string passed in.

Does not depend on any python.
""",
    implementation = _whl_archive_impl,
    environ = [
        REPO_DEBUG_ENV_VAR,
    ],
)
