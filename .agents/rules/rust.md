---
trigger: glob
description: Rust coding, dependency vetting, and rules_rust crate conventions
globs: "*.rs,Cargo.toml,Cargo.lock,Cargo.Bazel.lock,MODULE.bazel"
---

# Rust Conventions

## Standard Libraries Over Custom Subsystems
* Prefer `std` and established ecosystem crates (consult
  `https://blessed.rs/crates`) over implementing non-trivial subsystems from
  scratch.
* Never hand-roll CLI argument parsers (`lexopt` or `clap`), `@flagfile`
  response-file readers (`argfile`), CSV/INI/JSON/TOML format parsers (`csv`,
  etc.), base64/hex codecs (`base64`), language or packaging-spec parsers
  (`ruff_python_parser`, `pep440_rs`, `pep508_rs`), regex engines (`regex`),
  archive/compression codecs (`zip`, `flate2`), or cryptographic hashes
  (`sha2`).

## Dependency Vetting & Versioning
When adding or updating a Rust crate dependency:
* **Verify legitimacy**: Confirm the crate's maintainers and source repository
  on `crates.io` (prefer established organizations such as `rust-lang`,
  `rust-cli`, `RustCrypto`, `astral-sh`, or `zip-rs`), check corporate
  `cargo-vet` audit logs (Google/ChromeOS or Mozilla `audits.toml`), and check
  `rustsec.org` for advisories.
* **Use the latest version**: Query `index.crates.io` or `crates.io` and pin
  the latest non-yanked stable release. Document any version ceiling required
  by MSRV or cross-compilation platform constraints in a comment next to the
  dependency spec.
* **Keep default features unless problematic**: Leave crate default features
  enabled by default. Set `default_features = False` only when defaults pull in
  C `-sys` libraries (breaking hermetic cross-compiled and static `musl`
  builds), platform-incompatible OS crates, or heavy unused subsystems, and
  document the reason in a comment.
* **Regenerate lockfiles**: Update `Cargo.lock` and `Cargo.Bazel.lock` with
  `CARGO_BAZEL_REPIN=1`; never hand-edit generated lockfiles.

## Idiomatic Rust, CLI Design & Crate Layout
* **Edition & control flow**: Use `edition = "2024"`. Flatten nested
  conditionals with early `continue`/`return` guards and `let`-chains
  (`if let Some(p) = out.parent() && !p.as_os_str().is_empty()`). Prefer `str`
  pattern methods (`split_once`, `rsplit_once`, `strip_prefix`, `strip_suffix`)
  over manual index slicing.
* **Parse, don't validate**: Parse CLI flags and raw inputs into strong types
  (`bool`, enums, validated `PathBuf`, pre-compiled `Regex`) in `parse_args`
  rather than storing stringly-typed `String` fields or deferring validation to
  execution.
* **Positional argument counts**: Validate fixed positional argument counts with
  an explicit length check (e.g., `if positional.len() != 3`) rather than
  collection-length match guards or fixed-size array `try_from` conversions.
* **`OsString` & `ExitCode`**: Keep CLI arguments and file paths as `OsString`
  and `PathBuf`; never round-trip `OsString -> String -> PathBuf` via
  `to_string_lossy()`. Return `std::process::ExitCode` from `main()` and
  `run_cli`.
* **Symbolic constants in `match` arms**: When string tokens (subcommand names,
  CLI flags, or wire-format tags) appear across multiple sites (`match` arms,
  registries, or error messages), group them as constants in a module (`mod
  flags`, `mod subcommands`) and match via qualified paths (`flags::TEMPLATE`,
  `subcommands::ZIPPER`). A misspelled bare identifier in a Rust `match` arm
  parses as a catch-all variable binding, whereas a module-qualified path fails
  compilation (`E0531`). Keep raw string literals in tests so tests catch typos
  in constant values, and pass `case=no` to `keep-sorted` when `_` vs.
  uppercase ASCII would invert runtime lowercase sort order (`"zip_main_maker"`
  < `"zipper"`, whereas `ZIPPER` < `ZIP_MAIN_MAKER`).
* **Collections**: Default to `Vec` and `HashMap`/`HashSet` over
  `BTreeMap`/`BTreeSet` (and over `Vec<(K, V)>` linear scans when insertion
  order is not required) unless sorted-key traversal is a data-structure
  invariant. Sort a `Vec` at formatting or output boundaries when deterministic
  order is required; omit defensive key sorting when template placeholders are
  disjoint delimited tokens (e.g., `%KEY%`).
* **Cohesive file organization**: Place core logic in library crates
  (`src/lib.rs`) so unit tests call library functions directly, and extract
  shared wire/manifest parsers into a small workspace library crate rather than
  duplicating line parsing across sibling `shrubbery` crates. Group CLI
  option structs, `parse_args`, and `run_cli` together in one contiguous
  section rather than splitting `parse_args` at the top and `run_cli` at the
  bottom around domain logic.
* **Formatting**: Format Rust sources with `bazel run @rules_rust//:rustfmt`
  and verify with `--aspects=@rules_rust//rust:defs.bzl%rustfmt_aspect`
  `--output_groups=+rustfmt_checks`.

## Errors, Panics & Linting
* **Return errors, don't panic**: Production crates (`crates/*/src/*.rs`)
  carry `#![deny(clippy::expect_used, clippy::unwrap_used)]`; propagate
  with `?` and attach context so every failure names the path, line, or
  entry it concerns. Reach for `const` values (e.g.
  `zip::DateTime::DEFAULT`) instead of `.expect()` on infallible
  constructors.
* **Choose the error type by audience**: For CLI tools and other code that
  owns the error-handling context (the `shrubbery` subcommand crates), use
  `anyhow` (`bail!`, `.context()`, `.with_context(|| ...)`) and print the
  chain with `{err:#}` in `run_cli`. For library code consumed by other
  crates, define a typed error (`thiserror` enum implementing
  `std::error::Error` with `#[from]`/`#[source]`) so callers can match on
  variants and errors compose across crate boundaries; such a type still
  converts into `anyhow::Error` for free at the CLI layer.
* **Tests may panic**: `unwrap()`, `expect()`, `panic!`, and indexing are
  allowed in test code (`.clippy.toml` sets `allow-*-in-tests`). When using
  `expect()`, write the message in std's recommended style, stating why the
  value *should* be `Ok`/`Some` (`"manifest should be writable"`,
  `"output zip should be a valid archive"`), not the action that failed
  (`"write manifest"`).
* **Lints run on every build**: `.bazelrc` applies the clippy and rustfmt
  aspects by default (`--config=rust-lint`, `-Dwarnings`), so a plain
  `bazel build` fails on lint or formatting problems. Do not add
  `-Dclippy::unwrap_used`/`expect_used` globally: clippy's
  `allow-*-in-tests` settings only recognize `#[test]` functions and
  `#[cfg(test)]` items, so helper functions in integration-test crates
  (`tests/*/*_test.rs`) would be flagged. Code under `#[cfg(unix)]` must
  leave no `unused_mut`/`useless_vec` behind on Windows: initialize base
  collections as fixed-size arrays (`[...]`) or strings rather than `vec![...]`
  before rebinding under `#[cfg(unix)]` (spot-check the non-Unix branch locally
  on Linux by temporarily flipping `#[cfg(unix)]` to `#[cfg(windows)]` before
  pushing).
* **WORKSPACE-mode stub**: Any new `@rules_rust//...` flag or aspect
  referenced from `.bazelrc` must also exist in
  `tests/modules/rules_rust_stub/`, which WORKSPACE CI jobs use in place of
  rules_rust.
