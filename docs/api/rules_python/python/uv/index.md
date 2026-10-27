:::{default-domain} bzl
:::
:::{bzl:currentfile} //python/uv:BUILD.bazel
:::

# //python/uv

::::{bzl:target} current_toolchain

Exposes the resolved `uv` toolchain for the target/execution platform as an
executable target and template variable provider (`$(UV_BIN)`).

Can be run directly with `bazel run`:

```sh
bazel run @rules_python//python/uv:current_toolchain -- --help
```

:::{versionadded} VERSION_NEXT_FEATURE
:::
::::

:::{bzl:target} uv_toolchain_type

Toolchain type identifier for the `uv` toolchain, implemented by
{obj}`uv_toolchain`.
:::
