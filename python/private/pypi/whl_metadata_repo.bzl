"""
This is a repo rule for downloading lots of METADATA files and then comparing them.
"""

load("@pythons_hub//:interpreters.bzl", "INTERPRETER_LABELS")
load("//python/private:repo_utils.bzl", "repo_utils")
load("//python/private:text_util.bzl", "render")
load(":deps.bzl", "record_files")
load(":parse_requirements.bzl", "host_platform")
load(":pypi_repo_utils.bzl", "pypi_repo_utils")
load(":simpleapi_download.bzl", "simpleapi_download")
load(":whl_metadata.bzl", "parse_whl_metadata")

# Used as a default value in a rule to ensure we fetch the dependencies.
PY_SRCS = [
    # When the version, or any of the files in `packaging` package changes,
    # this file will change as well.
    record_files["pypi__packaging"],
    Label("//python/private/pypi/whl_installer:platform.py"),
    Label("//python/private/pypi/whl_installer:wheel_deps.py"),
]

def _impl(rctx):
    logger = repo_utils.logger(rctx)
    result = rctx.download(url = [rctx.attr.stats_url], output = "stats.json")
    if not result.success:
        fail(result)

    stats = json.decode(rctx.read("stats.json"))
    packages = [k["project"] for k in stats["rows"][:rctx.attr.limit]]

    data = simpleapi_download(
        rctx,
        attr = struct(
            index_url = rctx.attr.index_url,
            index_url_overrides = {},
            extra_index_urls = [],
            sources = packages,
            envsubst = [],
            netrc = None,
            auth_patterns = None,
        ),
        cache = {},
    )
    metadata_files = {}
    for pkg, d in data.items():
        last_version = d.sha256_by_version.keys()[-1]
        shas = d.sha256_by_version[last_version]
        whls = [
            d.whls[sha]
            for sha in shas
            if sha in d.whls
        ]
        if not whls:
            logger.warn("{} does not have any wheels, skipping".format(pkg))
            continue

        whl = whls[0]
        metadata_files[pkg] = (
            whl.metadata_url,
            whl.metadata_sha256,
        )

    downloads = {
        pkg + ".METADATA": rctx.download(
            url = [url],
            output = pkg + ".METADATA",
            sha256 = sha256,
            block = False,
        )
        for pkg, (url, sha256) in metadata_files.items()
    }

    rctx.file("BUILD.bazel", "")
    rctx.file("REPO.bazel", "")

    # TODO @aignas 2025-05-02: Change the algorithm to first:
    # Run a single execution of Python for each version where in one go we parse all of the METADATA files
    #
    # Then in a second loop we do the same for starlark whilst passing the python versions that we got.
    METADATA = {}
    for fname, d in downloads.items():
        result = d.wait()
        if not result.success:
            fail(fname)

        contents = rctx.read(fname)
        parsed = parse_whl_metadata(contents)

        METADATA[fname[:-len(".METADATA")]] = {
            "provides_extra": parsed.provides_extra,
            "requires_dist": parsed.requires_dist,
        }

    rctx.file("packages.txt", "\n".join(METADATA.keys()))

    py_parsed_deps = {}
    for py in rctx.attr.interpreters:
        output = pypi_repo_utils.execute_checked(
            rctx,
            op = "ParseDeps({})".format(py),
            python = pypi_repo_utils.resolve_python_interpreter(
                rctx,
                python_interpreter = None,
                python_interpreter_target = py,
            ),
            arguments = [
                "-m",
                "python.private.pypi.whl_installer.wheel_deps",
                "packages.txt",
            ],
            srcs = PY_SRCS,
            environment = {
                "PYTHONPATH": [
                    Label("@pypi__packaging//:BUILD.bazel"),
                    Label("//:BUILD.bazel"),
                ],
            },
            logger = logger,
        )
        if output.return_code != 0:
            # We have failed
            fail(output)

        decoded = json.decode(rctx.read("packages.txt.out"))
        python_version = decoded["version"]

        for name, deps in decoded["deps"].items():
            py_parsed_deps.setdefault(name, {})[python_version] = deps

    def _render_dict_of_dicts(outer):
        return render.dict(
            {
                k: render.dict(inner)
                for k, inner in outer.items()
            },
            value_repr = str,
        )

    defs_bzl = [
        "{} = {}".format(k, v)
        for k, v in {
            "HOST_PLATFORM": repr(host_platform(rctx)),
            "METADATA": _render_dict_of_dicts(METADATA),
            "WANT": _render_dict_of_dicts(py_parsed_deps),
        }.items()
    ]

    rctx.file("defs.bzl", "\n\n".join(defs_bzl))

whl_metadata_repo = repository_rule(
    implementation = _impl,
    attrs = {
        "index_url": attr.string(default = "https://pypi.org/simple"),
        "interpreters": attr.label_list(default = INTERPRETER_LABELS.values()),
        "limit": attr.int(default = 5000),
        "stats_url": attr.string(default = "https://hugovk.github.io/top-pypi-packages/top-pypi-packages.min.json"),
    },
)
