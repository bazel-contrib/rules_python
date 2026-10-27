"""Manifest of prebuilt tool binaries.

Empty in git, so source checkouts build the tools from source. The release
process replaces this file in the release archive with one whose
`ARTIFACTS_MANIFEST_JSON` holds the JSON manifest of the release's binaries.

It's a .bzl file so the `config` extension can load it rather than read it by
Label, which would make Bazel's remote repository contents cache materialize
the entire repository.
"""

ARTIFACTS_MANIFEST_JSON = ""
