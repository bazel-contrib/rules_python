:::{default-domain} bzl
:::
:::{bzl:currentfile} //python/uv:BUILD.bazel
:::

# //python/uv

::::{bzl:target} current_toolchain

Exposes the resolved `uv` toolchain for the target/execution platform as an
executable target and template variable provider (`$(UV)` and `$(UV_BIN)`).

Can be run directly with `bazel run`:

```sh
bazel run @rules_python//python/uv:current_toolchain -- --help
```

Or integrated with
[`bazel_env.bzl`](https://github.com/buildbuddy-io/bazel_env.bzl) to expose
`uv` on your local `PATH`:

```bzl
bazel_env(
    name = "bazel_env",
    toolchains = {
        "uv": "@rules_python//python/uv:current_toolchain",
    },
    tools = {
        "uv": "$(UV)",
    },
)
```

:::{versionadded} VERSION_NEXT_FEATURE
:::
::::

:::{bzl:target} uv_toolchain_type

Toolchain type identifier for the `uv` toolchain, implemented by
{obj}`uv_toolchain`.
:::
