:::{default-domain} bzl
:::
:::{bzl:currentfile} //python/uv/bin:BUILD.bazel
:::

# //python/uv/bin

Executable aliases for the configured `uv` binary. These targets can be run
directly with `bazel run` or passed to tools such as
[`bazel_env.bzl`](https://github.com/buildbuddy-io/bazel_env.bzl) (or via
{obj}`//python/uv:current_toolchain` and `$(UV)`).

::::{bzl:target} bin

Alias for {obj}`//python/uv:current_toolchain` to directly run the configured
`uv` binary:

```sh
bazel run @rules_python//python/uv/bin -- --help
```

:::{versionadded} VERSION_NEXT_FEATURE
:::
::::

::::{bzl:target} uv

Alias for {obj}`//python/uv:current_toolchain` to directly run the configured
`uv` binary:

```sh
bazel run @rules_python//python/uv/bin:uv -- --help
```

:::{versionadded} VERSION_NEXT_FEATURE
:::
::::
