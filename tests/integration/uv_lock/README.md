# uv_lock integration test workspace

This directory is a self-contained Bazel workspace used by the
`//tests/integration:uv_lock_test` (bzlmod) and
`//tests/integration:uv_lock_workspace_test` (WORKSPACE) integration tests.

It demonstrates how to use the `lock()` macro from `@rules_python//python/uv`
to pin requirements with `uv pip compile`. `MODULE.bazel` configures the `uv`
toolchains via the `uv` module extension; `WORKSPACE` does the same via
`uv_toolchains_manifest()` and `uv_register_toolchains()`. The empty
`WORKSPACE.bzlmod` keeps Bazel 7 from evaluating `WORKSPACE` when bzlmod is
enabled.

## Targets

| Target | Description |
|--------|-------------|
| `//:requirements` | Build action that produces the locked requirements file |
| `//:requirements.update` | Update the in-source `requirements.txt` via `bazel run` |
| `//:requirements.run` | Run `uv pip compile` with extra command-line args |
| `//:requirements_diff_test` | Diff test comparing the lock output to the in-source file |
| `//:uv` | The `uv` binary from the registered toolchain |

## Workflow for debugging

If you want to debug and play around, you can start the server and then run the uv lock command
manually.

### Start the local PyPI server

In a separate terminal, start the pypiserver that serves the `my-local-pkg` test wheel:

```shell
bazel run //tests/integration:uv_lock_pypi_server [-- --no-auth]
```

The server prints the URL to use (with and without authentication) and the
SHA256 of the wheel.  Pass `--no-auth` to allow anonymous access.

### Lock the requirements

With the server running, lock the requirements from this directory:

```shell
cd tests/integration/uv_lock
bazel run //:requirements.update               \
    --action_env=UV_EXTRA_INDEX_URL="<auth-url>" \
    --action_env=UV_CREDENTIALS_DIR=<creds-dir>
```

The `<auth-url>` and `<creds-dir>` values are printed by the pypi-server.

### Verify the lock output matches the in-source file

```shell
bazel test //:requirements_diff_test
```

## bazel-in-bazel Testing

When iterating on changes to `lock.bzl`, the integration test can be run
directly from rules_python:

```shell
bazel test //tests/integration:uv_lock_test_bazel_self \
    --config=fast-tests \
    --test_output=streamed \
    --test_filter=<test_name>
```

The WORKSPACE variant runs the same Python test cases with
`--noenable_bzlmod --enable_workspace`, e.g.
`//tests/integration:uv_lock_workspace_test_bazel_8.5.1`. It only exists for
Bazel 7.x and 8.x because Bazel 9 ignores `WORKSPACE` files.
