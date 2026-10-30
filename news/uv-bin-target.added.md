(uv) Added `@uv//:uv`, {obj}`//python/uv/bin:uv`, and public visibility on
{obj}`//python/uv:current_toolchain` (along with the `$(UV)` make variable) to
run the configured `uv` binary directly (e.g.
`bazel run @rules_python//python/uv/bin:uv -- --help` or
`bazel run @uv -- --help`)
([#4371](https://github.com/bazel-contrib/rules_python/pull/4371)).
