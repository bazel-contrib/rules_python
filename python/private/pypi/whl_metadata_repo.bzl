""

load("@pythons_hub//:interpreters.bzl", "INTERPRETER_LABELS")
load("//python/private:normalize_name.bzl", "normalize_name")
load("//python/private:repo_utils.bzl", "repo_utils")
load("//python/private:text_util.bzl", "render")
load(":deps.bzl", "record_files")
load(":parse_requirements.bzl", "host_platform")
load(":pep508_deps.bzl", "deps")
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
    data = simpleapi_download(
        rctx,
        attr = struct(
            index_url = "https://pypi.org/simple",
            index_url_overrides = {},
            extra_index_urls = [],
            sources = rctx.attr.distros,
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
        whl = [
            d.whls[sha]
            for sha in shas
            if sha in d.whls
        ][0]
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

    defs_bzl = {
        "HOST": repr(host_platform(rctx)),
    }

    for fname, d in downloads.items():
        result = d.wait()
        if not result.success:
            fail(fname)

        contents = rctx.read(fname)
        parsed = parse_whl_metadata(contents)
        target_platforms = [host_platform(rctx)]

        parsed_deps = {}
        py_parsed_deps = {}
        for py in rctx.attr.interpreters:
            output = pypi_repo_utils.execute_checked(
                rctx,
                op = "ParseDeps({})".format(fname),
                python = pypi_repo_utils.resolve_python_interpreter(
                    rctx,
                    python_interpreter = None,
                    python_interpreter_target = py,
                ),
                arguments = [
                    "-m",
                    "python.private.pypi.whl_installer.wheel_deps",
                    fname,
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

            decoded = json.decode(output.stdout)
            python_version = decoded["version"]

            py_parsed_deps[python_version] = decoded["deps"]
            parsed_deps[python_version] = deps(
                name = normalize_name(parsed.name),
                requires_dist = parsed.requires_dist,
                platforms = target_platforms,
                excludes = [],
                extras = [],
                default_python_version = python_version,
            ).deps

        result = {
            "give_name": repr(parsed.name),
            "give_provides_extra": render.list(parsed.provides_extra),
            "give_requires_dist": render.list(parsed.requires_dist),
            "got_deps": render.dict(parsed_deps, value_repr = render.list),
            "want_deps": render.dict(py_parsed_deps, value_repr = render.list),
        }

        defs_bzl.setdefault("METADATA", []).append(result)

    defs_bzl["METADATA"] = render.list(
        defs_bzl["METADATA"],
        repr = lambda x: render.dict(x, value_repr = str),
    )

    defs_bzl = [
        "{} = {}".format(k, v)
        for k, v in defs_bzl.items()
    ] + [
        """def whl_metadata_parsing_test_suite(name):
    native.test_suite(
        name = name,
        tests = [],
    )""",
    ]

    rctx.file("defs.bzl", "\n\n".join(defs_bzl))

whl_metadata_repo = repository_rule(
    implementation = _impl,
    attrs = {
        "distros": attr.string_list(default = [
            "numpy",
            "torch",
            "redis",
        ]),
        "interpreters": attr.label_list(default = list(INTERPRETER_LABELS.values())[:5]),
    },
)
