:::{default-domain} bzl
:::
:::{bzl:currentfile} //python/uv/bin:BUILD.bazel
:::

# //python/uv/bin

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
