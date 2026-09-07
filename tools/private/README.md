# Internal Tools (`//tools/private`)

This directory contains internal private tools and dependencies used by
`//tools` (such as `publish_deps.bzl`).

Supporting tools for rules (e.g. `launcher`, `precompiler`, `zipapp`,
`publish`, `wheelmaker`) belong as their own top-level directories under
`//tools/`.

Developer-only tools (such as release management and dependency updating)
belong under `//dev/`.
