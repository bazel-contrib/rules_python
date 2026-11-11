"""The coverage tool for the WORKSPACE toolchains.

The bzlmod toolchains use the `@rules_python_coverage` pip hub, which is
created from the `uv.lock` file. The WORKSPACE macros cannot read the
`uv.lock` file, so it is vendored to the `uv_lock.bzl` file by the
`vendor_uv_lock` macro and this creates an equivalent hub repository from it
with the same wheel selection as the `pip.parse` extension.

The WORKSPACE builds do not set the Python version flag by default, so there
is a target for each Python version in the hub, which only selects the wheel
based on the target platform.
"""

load("@bazel_tools//tools/build_defs/repo:utils.bzl", "maybe")
load("//python:versions.bzl", "MINOR_MAPPING")
load("//python/private:text_util.bzl", "render")
load("//python/private:version.bzl", "version")
load("//python/private/pypi:default_platforms.bzl", "default_platforms")
load("//python/private/pypi:hash.bzl", "hash")
load("//python/private/pypi:parse_requirements.bzl", "parse_requirements")
load("//python/private/pypi:pep508_env.bzl", "env")
load("//python/private/pypi:pep508_evaluate.bzl", "evaluate")
load("//python/private/pypi:platform.bzl", "platform")
load("//python/private/pypi:whl_library.bzl", "whl_library")
load("//python/private/pypi:whl_repo_name.bzl", "whl_repo_name")
load(":uv_lock.bzl", "UV_LOCK_JSON")

_HUB_NAME = "rules_python_coverage"

def _noop(*_args, **_kwargs):
    return None

# The selection runs in WORKSPACE macros, which have no repository context to
# create a logger from.
_LOGGER = struct(
    trace = _noop,
    debug = _noop,
    info = _noop,
    warn = _noop,
    fail = lambda message_cb: fail(message_cb()),
    failed = lambda: False,
)

def _coverage_hub_repo_impl(rctx):
    platforms = json.decode(rctx.attr.platforms)
    tools = json.decode(rctx.attr.tools)

    used_platforms = sorted({
        p: None
        for by_platform in tools.values()
        for p in by_platform
    })

    rctx.file("BUILD.bazel", "\n".join([
        """load("@bazel_skylib//lib:selects.bzl", "selects")""",
        "",
        """package(default_visibility = ["//visibility:public"])""",
        "",
        """exports_files(["config.bzl"])""",
        "",
    ] + [
        render.call(
            "selects.config_setting_group",
            name = repr("is_" + p),
            match_all = render.list(platforms[p]),
        ) + "\n"
        for p in used_platforms
    ]))

    # The `whl_library` repositories load the packages from the hub.
    rctx.file("config.bzl", "packages = {\"coverage\": None}\n")

    rctx.file("coverage/BUILD.bazel", "\n".join([
        """package(default_visibility = ["//visibility:public"])""",
        "",
    ] + [
        render.alias(
            name = python_version,
            actual = render.select(
                {
                    "//:is_" + p: "@{}_{}//:pkg".format(rctx.attr.name, name)
                    for p, name in sorted(by_platform.items())
                },
                no_match_error = repr((
                    "There is no coverage wheel for Python {} on the target " +
                    "platform. See the `python/private/coverage/uv.lock` " +
                    "file in rules_python for the supported platforms."
                ).format(python_version)),
            ),
        ) + "\n"
        for python_version, by_platform in sorted(tools.items())
    ]))

coverage_hub_repo = repository_rule(
    implementation = _coverage_hub_repo_impl,
    attrs = {
        "platforms": attr.string(
            mandatory = True,
            doc = "JSON encoded dict of platform names to config setting labels.",
        ),
        "tools": attr.string(
            mandatory = True,
            doc = "JSON encoded dict of Python versions to platform names to wheel names.",
        ),
    },
    doc = "The hub repository for the coverage tool of the WORKSPACE toolchains.",
)

def _platforms(python_version, platforms):
    """Return the platforms to select the wheels for.

    Args:
        python_version: {type}`str` the full Python version.
        platforms: {type}`dict[str, dict]` the platform definitions, see
            `default_platforms`.

    Returns:
        {type}`dict[str, struct]` the platforms.
    """
    ver = version.parse(python_version, strict = True)
    ret = {}
    for name, values in platforms.items():
        p = platform(**values)
        env_ = env(
            env = p.env,
            os = p.os_name,
            arch = p.arch_name,
            python_version = python_version,
        )
        if p.marker and not evaluate(p.marker, env = env_):
            continue

        ret[name] = struct(
            env = env_,
            whl_abi_tags = [
                tag.format(major = ver.release[0], minor = ver.release[1])
                for tag in p.whl_abi_tags
            ],
            whl_platform_tags = p.whl_platform_tags,
        )
    return ret

def select_wheels(*, uv_lock, minor_mapping, platforms, package = "coverage"):
    """Select the wheels of a package with the same selection as `pip.parse`.

    Args:
        uv_lock: {type}`dict` the decoded `uv.lock` file.
        minor_mapping: {type}`dict[str, str]` the Python versions to select
            the wheels for, e.g. `{"3.13": "3.13.1"}`.
        platforms: {type}`dict[str, dict]` the platform definitions, see
            `default_platforms`.
        package: {type}`str` the name of the package to select the wheels for.

    Returns:
        {type}`struct` with `wheels`, a dict of repository name suffixes to
        the wheel `filename`, `integrity`, `requirement` and `url`, and
        `tools`, a dict of
        `major.minor` versions to platform names to the repository name
        suffixes.
    """
    wheels = {}
    tools = {}
    for minor_version, full_version in sorted(
        minor_mapping.items(),
        key = lambda x: version.parse(x[0]).key(),
    ):
        requirements = parse_requirements(
            # The lock file is already decoded, so there is nothing to read.
            struct(read = lambda _: ""),
            platforms = _platforms(full_version, platforms),
            uv_lock = "uv.lock",
            toml_decode = lambda _: uv_lock,
            logger = _LOGGER,
        )
        for whl in requirements:
            if whl.name != package:
                continue

            for src in whl.srcs:
                if not src.filename.endswith(".whl"):
                    continue

                name = whl_repo_name(src.filename, src.digest)
                wheels[name] = {
                    "filename": src.filename,
                    "integrity": hash.integrity(src.digest),
                    "requirement": src.requirement_line,
                    "url": src.url,
                }
                for p in src.target_platforms:
                    tools.setdefault(minor_version, {})[p] = name

    return struct(wheels = wheels, tools = tools)

def coverage_repositories(*, name, uv_lock, python_version, minor_mapping = MINOR_MAPPING, platforms = None):
    """Create the coverage wheel repositories and the hub repository.

    Args:
        name: {type}`str` the name of the hub repository.
        uv_lock: {type}`dict` the decoded `uv.lock` file.
        python_version: {type}`str` the full Python version of the toolchain.
        minor_mapping: {type}`dict[str, str]` the Python versions to create
            the coverage tool for.
        platforms: {type}`dict[str, dict] | None` the platform definitions,
            defaults to `default_platforms`.

    Returns:
        {type}`str | None` the label of the coverage tool or `None` if there
        are no coverage wheels for the Python version.
    """
    major_minor = ".".join(python_version.split(".")[:2])

    # This is called for each toolchain platform, so only select the wheels
    # once.
    existing = native.existing_rule(name)
    if existing:
        tools = json.decode(existing["tools"])
    else:
        platforms = platforms or default_platforms()
        selected = select_wheels(
            uv_lock = uv_lock,
            minor_mapping = minor_mapping,
            platforms = platforms,
        )
        tools = selected.tools
        for repo, whl in selected.wheels.items():
            maybe(
                whl_library,
                name = "{}_{}".format(name, repo),
                requirement = whl["requirement"],
                urls = [whl["url"]],
                filename = whl["filename"],
                integrity = whl["integrity"],
                dep_template = "@{}//{{name}}:{{target}}".format(name),
                config_load = "@{}//:config.bzl".format(name),
            )

        coverage_hub_repo(
            name = name,
            platforms = json.encode({
                p: [str(Label(setting)) for setting in values["config_settings"]]
                for p, values in platforms.items()
            }),
            tools = json.encode(tools),
        )

    if major_minor not in tools:
        return None

    return "@{}//coverage:{}".format(name, major_minor)

def coverage_tool(python_version):
    """Create the coverage repositories and return the coverage tool label.

    Args:
        python_version: {type}`str` the full Python version of the toolchain.

    Returns:
        {type}`str | None` the label of the coverage tool or `None` if there
        are no coverage wheels for the Python version.
    """
    return coverage_repositories(
        name = _HUB_NAME,
        uv_lock = json.decode(UV_LOCK_JSON),
        python_version = python_version,
    )
