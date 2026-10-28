"""Manifest of prebuilt tool binaries.

Empty in git, so source checkouts build the tools from source. The release
process replaces this file in the release archive with one whose
`ARTIFACTS_MANIFEST_JSON` holds the JSON manifest of the release's binaries.

It's a .bzl file so the `config` extension can load it rather than read it by
Label, which would make Bazel's remote repository contents cache materialize
the entire repository. Once https://github.com/bazelbuild/bazel/pull/31493
lands, reading by Label no longer materializes, and this can go back to being
a plain JSON file.
"""

# A JSON string rather than Starlark values, so the builtin manifest is parsed
# by the same code path as a custom prebuilt tools manifest.
ARTIFACTS_MANIFEST_JSON = ""
