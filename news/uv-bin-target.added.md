(uv) Added `@uv//:uv`, {obj}`//python/uv/bin:uv`,
{obj}`//python/uv/bin:bin`, and public visibility on
{obj}`//python/uv:current_toolchain` (along with the `$(UV)` make variable) to
run the configured `uv` binary directly (e.g.
`bazel run @uv//:uv -- --help`).
