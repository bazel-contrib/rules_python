:::{default-domain} bzl
:::

# Lock

:::{note}
`rules_python` supports `requirements.txt` and `uv.lock` (bzlmod only)
formats.

#{gh-issue}`2787` tracks `pylock.toml` support.
:::

## requirements.txt

### pip compile

Generally, when working on a Python project, you'll have some dependencies that themselves have
other dependencies. You might also specify dependency bounds instead of specific versions.
So you'll need to generate a full list of all transitive dependencies and pinned versions
for every dependency.

Typically, you'd have your project dependencies specified in `pyproject.toml` or `requirements.in`
and generate the full pinned list of dependencies in `requirements_lock.txt`, which you can
manage with {obj}`compile_pip_requirements`:

```starlark
load("@rules_python//python:pip.bzl", "compile_pip_requirements")

compile_pip_requirements(
    name = "requirements",
    src = "pyproject.toml",
    requirements_txt = "requirements_lock.txt",
)
```

This rule generates two targets:
- `bazel run [name].update` will regenerate the `requirements_txt` file
- `bazel test [name]_test` will test that the `requirements_txt` file is up to date

Once you generate this fully specified list of requirements, you can install the requirements ([bzlmod](./download)/[WORKSPACE](./download-workspace)).

:::{warning}
If you're specifying dependencies in `pyproject.toml`, make sure to include the
`[build-system]` configuration, with pinned dependencies.
`compile_pip_requirements` will use the build system specified to read your
project's metadata, and you might see non-hermetic behavior if you don't pin the
build system.

Not specifying `[build-system]` at all will result in using a default
`[build-system]` configuration, which uses unpinned versions
([ref](https://peps.python.org/pep-0518/#build-system-table)).
:::


#### pip compile Dependency groups

pip-compile doesn't yet support pyproject.toml dependency groups. Follow
[pip-tools #2062](https://github.com/jazzband/pip-tools/issues/2062)
to see the status of their support.

In the meantime, support can be emulated by passing multiple files to `srcs`:

```starlark
compile_pip_requirements(
    srcs = ["pyproject.toml", "requirements-dev.in"]
    ...
)
```

### uv pip compile

We also have a setup for the `uv pip compile` way of generating lock files.
This is well tested with the public PyPI index, but you may hit some rough
edges with private mirrors.

#### Setup

A `uv` toolchain has to be registered, as well as a Python toolchain, which
{obj}`lock` uses to run `uv` with a hermetic interpreter.

##### Bzlmod

`rules_python` registers the `uv` toolchains for you; `MODULE.bazel` only has
to configure the version to download with the {obj}`uv` module extension:

```starlark
uv = use_extension(
    "@rules_python//python/uv:uv.bzl",
    "uv",
    dev_dependency = True,
)
uv.configure(version = "0.13.5")
```

Without `version`, the default version specified by `rules_python` is used.
See {obj}`uv.configure` for using a mirror, explicit URLs or extra platforms.

(uv-workspace-setup)=
##### WORKSPACE

The setup has two steps: {obj}`uv_toolchains_manifest` fetches the release
manifests of the `uv` versions you want, and the {obj}`uv_register_toolchains`
it exposes creates the toolchains for the platforms those releases have
archives for and registers them:

```starlark
load("@rules_python//python/uv:repositories.bzl", "uv_toolchains_manifest")

uv_toolchains_manifest(
    name = "uv_manifest",
    versions = ["0.13.5"],
)

load("@uv_manifest//:dist_manifest.bzl", "uv_register_toolchains")

uv_register_toolchains(name = "uv")
```

Any released `uv` version can be fetched this way; the download URLs and
checksums are read from the release manifests. The `configure` argument of
{obj}`uv_register_toolchains` takes the same entries as {obj}`uv.configure`.

Bazel prefers toolchains in registration order, so to replace one of the
registered toolchains with your own, register yours before calling
`uv_register_toolchains()` and remove ours; to add one without configuring it
here, register yours after:

```starlark
uv_toolchains_manifest(
    name = "uv_manifest",
    versions = ["0.13.5", "0.6.5"],
)

load("@uv_manifest//:dist_manifest.bzl", "uv_register_toolchains")

# Preferred over the toolchains registered below.
register_toolchains("//tools/uv:patched_linux_toolchain")

uv_register_toolchains(
    name = "uv",
    configure = [
        # Replaced by the toolchain registered above.
        {"platform": "x86_64-unknown-linux-gnu"},
        # An additional platform for 0.13.5.
        {
            "platform": "aarch64-unknown-linux-musl",
            "compatible_with": [
                "@platforms//os:linux",
                "@platforms//cpu:aarch64",
            ],
            "target_settings": [Label("//tools/uv:is_musl")],
        },
        # The older version with the default platforms. Its toolchains
        # come after those of 0.13.5 in `@uv//:all`, so they are only
        # used where no earlier toolchain matches.
        {"version": "0.6.5"},
    ],
)

# Used only when none of the toolchains above match.
register_toolchains("//tools/uv:freebsd_toolchain")
```

Using a manifest is optional. Without {obj}`uv_toolchains_manifest`, load
{obj}`uv_register_toolchains` directly from
`@rules_python//python/uv:repositories.bzl` and specify `urls` for every
platform:

```starlark
load("@rules_python//python/uv:repositories.bzl", "uv_register_toolchains")

uv_register_toolchains(
    name = "uv",
    version = "0.13.5",
    configure = [
        {
            "platform": "x86_64-unknown-linux-gnu",
            "urls": ["https://mirror.example.com/uv/uv-0.13.5-x86_64-unknown-linux-gnu.tar.gz"],
            "sha256": "...",
        },
    ],
)
```

#### Example usage

```starlark
load("@rules_python//python/uv:lock.bzl", "lock")

lock(
    name = "requirements",
    srcs = ["pyproject.toml", "requirements.in"],
    out = "requirements_lock.txt",
)
```

#### `[tool.uv]` settings from pyproject.toml

When a `pyproject.toml` file is among the {arg}`lock.srcs`, the
{obj}`lock` rule auto-detects the project directory and passes
`--project <dir>` to `uv`. This causes `uv` to read
`[tool.uv]` settings from that `pyproject.toml`, such as
`no-build-isolation`, `exclude-dependencies`, and workspace members.

If multiple `pyproject.toml` files are in {arg}`lock.srcs`, the one
with the shortest directory path is selected (this heuristic works for
typical uv workspace layouts where the root configuration is at the
shortest path).

If the auto-detection picks the wrong project directory, use the
`project` parameter to override:

```starlark
lock(
    name = "requirements",
    srcs = ["pyproject.toml", "requirements.in"],
    out = "requirements_lock.txt",
    project = "subproject",
)
```

:::{warning}
**Known limitations of auto-detection**

1. **Workspace heuristic** — the shortest-path selection may incorrectly assume
   the upper-most workspace `pyproject.toml` is the correct one. For monorepos
   with multiple independent sub-projects, you must set `project` explicitly
   for each {obj}`lock` target.
1. **No test target** — unlike {obj}`compile_pip_requirements`, no test target
   is auto-created; see the {obj}`lock` docs for how to add one manually using
   `diff_test` from `bazel_skylib`.
:::

## uv.lock (bzlmod only)

The {obj}`lock` rule also supports generating cross-platform `uv.lock` files
using `uv lock` when {arg}`lock.out` ends with `.lock` (such as `uv.lock`).

### Example usage

In `BUILD.bazel`:

```starlark
load("@rules_python//python/uv:lock.bzl", "lock")

lock(
    name = "uv_lock",
    srcs = ["pyproject.toml"],
    out = "uv.lock",
)
```

Run `bazel run //:uv_lock.update` to generate or update `uv.lock`, then pass it
to {obj}`pip.parse` in `MODULE.bazel` via {attr}`pip.parse.uv_lock`:

```starlark
pip = use_extension("@rules_python//python/extensions:pip.bzl", "pip")
pip.parse(
    hub_name = "my_deps",
    python_version = "3.13",
    uv_lock = "//:uv.lock",
)
use_repo(pip, "my_deps")
```

`[tool.uv]` settings auto-detection and the {arg}`lock.project` attribute work
the same way as described in the `uv pip compile` section above.

For more documentation see {obj}`lock`.
