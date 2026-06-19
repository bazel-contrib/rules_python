:::{default-domain} bzl
:::

# Lock

:::{note}
Currently `rules_python` only supports `requirements.txt` format.

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
    src = "requirements.in",
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

### uv pip compile (bzlmod only)

We also have an experimental setup for the `uv pip compile` way of generating lock files.
This is well tested with the public PyPI index, but you may hit some rough edges with private
mirrors.

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

When a `pyproject.toml` file is among the {attr}`lock.srcs`, the
{obj}`lock` rule auto-detects the project directory and passes
`--project <dir>` to `uv pip compile`. This causes `uv` to read
`[tool.uv]` settings from that `pyproject.toml`, such as
`no-build-isolation`, `exclude-dependencies`, and workspace members.

If multiple `pyproject.toml` files are in {attr}`lock.srcs`, the one
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

1. **Workspace heuristic** — the shortest-path selection may incorrectly assume the upper-most
   workspace `pyproject.toml` is the correct one. For monorepos with multiple independent
   sub-projects, you must set `project` explicitly for each {obj}`lock` target.
1. **No test target** — unlike {obj}`compile_pip_requirements`, no test target is auto-created; see
   the {obj}`lock` docs for how to add one manually using `diff_test` from `bazel_skylib`.
:::

For more documentation see {obj}`lock`.
