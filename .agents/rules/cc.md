# C/C++ Rules Design & Bazel rules_cc Integration

## Concise `cc_shared_library` Interface & Export Rules
* In `cc_shared_library`:
  * Targets directly placed in `deps` are **automatically exported** by Bazel;
    they do not need to be listed in `exports_filter`.
  * `exports_filter` is defined in `rules_cc` as an `attr.string_list()`, **not**
    a `Label` attribute. Passing Starlark `Label` objects directly causes an
    immediate Bazel analysis type error.
  * **Citation**: [rules_cc `cc_shared_library.bzl`](https://github.com/bazelbuild/rules_cc/blob/main/cc/private/rules_impl/cc_shared_library.bzl)
    (*"exports_filter is a list of strings attribute"*).

## macOS Dynamic Lookup Link Flag
* Apple's `ld64`/`lld` linkers require `-undefined dynamic_lookup` in
  `user_link_flags` on macOS so CPython C-API symbols remain unresolved at
  link time and resolve dynamically at runtime.

## Linux Platform Tag Composition
* Linux platform tags are formatted as `{platform_machine}-linux-{libc}` (e.g.,
  `x86_64-linux-gnu` or `aarch64-linux-musl`).
* **Citation**: [PEP 600 — Perennial manylinux](https://peps.python.org/pep-0600/)
  & [PEP 656 — musllinux](https://peps.python.org/pep-0656/).
