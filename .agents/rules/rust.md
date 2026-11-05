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
* **`OsString` & `ExitCode`**: Keep CLI arguments and file paths as `OsString`
  and `PathBuf`; never round-trip `OsString -> String -> PathBuf` via
  `to_string_lossy()`. Return `std::process::ExitCode` from `main()` and
  `run_cli`.
* **Collections**: Default to `Vec` and `HashMap`/`HashSet` over
  `BTreeMap`/`BTreeSet` unless sorted-key traversal is a data-structure
  invariant. Sort a `Vec` at formatting or output boundaries when deterministic
  order is required.
* **Cohesive file organization**: Place core logic in library crates
  (`src/lib.rs`) so unit tests call library functions directly. Group CLI
  option structs, `parse_args`, and `run_cli` together in one contiguous
  section rather than splitting `parse_args` at the top and `run_cli` at the
  bottom around domain logic.
* **Formatting**: Format Rust sources with `bazel run @rules_rust//:rustfmt`
  and verify with `--aspects=@rules_rust//rust:defs.bzl%rustfmt_aspect`
  `--output_groups=+rustfmt_checks`.
