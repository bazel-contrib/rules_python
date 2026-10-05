# Plan: dev-only toolchain for the Rust `exe_zip_maker`

## Background

PR #4151 added a Rust implementation of `exe_zip_maker` under
`//crates/exe_zip_maker`. It is built with `rules_rust`, which is a
`dev_dependency` of rules_python. Users of rules_python therefore cannot
build it, and in WORKSPACE mode `@rules_rust` is a stub that produces empty
`filegroup`s.

Today, `py_binary`/`py_test` (via `py_executable.bzl`) and `py_zipapp`
(via `py_zipapp_rule.bzl`) invoke the Python `//tools/zipapp:exe_zip_maker`
(a `py_interpreter_program`) through a private `_exe_zip_maker` attribute and
`actions_run()`.

## Goal

Use the Rust tool when developing rules_python itself (bzlmod only), while
leaving downstream users on the Python implementation with no behavior change.

## Design

Introduce a dedicated, optional toolchain type for the `exe_zip_maker` tool:

* `//python/private/toolchain_types:exe_zip_maker` (`toolchain_type`), in a
  new `python/private/toolchain_types/` package dedicated to internal
  toolchain types.
* No separate provider: the toolchain is tool-specific, so
  `ToolchainInfo(exe_zip_maker = Target | None)` is sufficient.
* `py_exe_zip_maker_toolchain` rule
  (`python/private/zipapp/py_exe_zip_maker_toolchain.bzl`) that returns the
  `ToolchainInfo` above. Its `exe_zip_maker` attr uses `cfg = "exec"` so the
  tool is built for the exec platform.
* Add `EXE_ZIP_MAKER_TOOLCHAIN_TYPE` to `python/private/toolchain_types.bzl`.
* Rules that create executable zips declare the toolchain as
  `mandatory = False`. When resolved and `exe_zip_maker` is set, use it;
  otherwise fall back to the existing `_exe_zip_maker` attribute (the Python
  tool). This keeps users and WORKSPACE mode unchanged: no new toolchain
  registration is required.
* Gated by a flag, disabled by default:
  `--//dev/dev_only_toolchains:use_rust_exe_zip_maker` (a `bool_flag` +
  `config_setting` used as the `toolchain()`'s `target_settings`).
* Dev-only registration: the `toolchain()` lives in
  `dev/dev_only_toolchains/` and its `py_exe_zip_maker_toolchain`
  implementation in `dev/dev_only_toolchains/impls/`, kept in separate
  packages so registration does not load the implementation. The
  implementation points at `//crates/exe_zip_maker`. It is registered in
  `MODULE.bazel` with `register_toolchains(..., dev_dependency = True)`.
  Nothing is registered in WORKSPACE mode (where the Rust binary is a stub).

Why a new toolchain type instead of extending `py_exec_tools_toolchain`?
The exec tools toolchain is created per-Python-version inside the hermetic
runtime repos and is coupled to the interpreter; overriding it just for dev
would require duplicating that setup. A small, separate toolchain type is
simpler.

Naming: tool-specific (`exe_zip_maker`). Future tools (zipper,
zip_main_maker) get their own toolchain types in the same package.

## Work items

- [x] Research current wiring (`py_executable.bzl`, `py_zipapp_rule.bzl`,
      `actions_run`, `py_exec_tools_toolchain`).
- [x] Add `EXE_ZIP_MAKER_TOOLCHAIN_TYPE` to `toolchain_types.bzl`.
- [x] Add `toolchain_type(name = "exe_zip_maker")` in
      `python/private/toolchain_types/BUILD.bazel`.
- [x] ~~Provider file~~ (dropped; tool-specific toolchain needs none).
- [x] Add `py_exe_zip_maker_toolchain.bzl` (`py_exe_zip_maker_toolchain` rule) +
      `bzl_library`.
- [x] Add helper `get_exe_zip_maker(ctx)` (in `py_exe_zip_maker_toolchain.bzl`)
      that prefers the toolchain and falls back to `ctx.attr._exe_zip_maker`.
- [x] Wire into `py_executable.bzl`: declare optional toolchain, use helper.
- [x] Wire into `py_zipapp_rule.bzl`: declare optional toolchain, use helper.
- [x] Define dev toolchain in `dev/dev_only_toolchains/BUILD.bazel`
      (`py_exe_zip_maker_toolchain` + `toolchain`).
- [x] Register dev toolchain in `MODULE.bazel` with `dev_dependency = True`.
- [x] Update `bzl_library` deps in `python/private/BUILD.bazel` and
      `python/private/zipapp/BUILD.bazel`.
- [x] Add analysis tests (`tests/exe_zip_maker_toolchain/`): Rust tool used
      for `py_binary` and `py_zipapp` when the flag is on; Python fallback
      when off.
- [x] Add `use_rust_exe_zip_maker` flag (default off) gating the toolchain.
- [x] Verify: `bazel build //crates/...`, `bazel test --config=fast-tests`
      on `//tests/exe_zip_maker_toolchain/... //tests/py_zipapp/...
      //tests/exe_zip_maker/... //tests/tools/zipapp/... //tests/base_rules/...`
      (98 pass, 4 skipped), `bazel build //docs:docs` (ok), buildifier (ok).
- [x] Verify WORKSPACE mode falls back to the Python tool. Bazel 9 has no
      WORKSPACE, so checked with `USE_BAZEL_VERSION=8.x` + `--noenable_bzlmod
      --enable_workspace`: both `PyBuildExecutableZip` and
      `PyZipAppCreateExecutableZip` invoke `tools/zipapp/exe_zip_maker_.py`.
- [x] News entry: skipped; dev-only, no user-visible behavior change
      (same as PR #4151).
- [ ] Create PR (pending user go-ahead).

## Progress log

* 2026-10-04: Plan written.
* 2026-10-04: Implementation done; bzlmod `aquery` shows both zip actions
  executing `bazel-out/.../crates/exe_zip_maker/exe_zip_maker`.
* 2026-10-04: Tests, docs, buildifier, WORKSPACE fallback all verified.
* 2026-10-04: Per review, renamed to be tool-specific
  (`//python/private/toolchain_types:exe_zip_maker`,
  `py_exe_zip_maker_toolchain`) and dropped the generic provider. Tests
  re-run and pass.

## Open questions / follow-ups

* Should the default (Python) tool also be delivered via a registered
  toolchain in a later change, so the attribute fallback can be removed?
* Later: add `zipper`/`zip_main_maker` toolchain types alongside.
