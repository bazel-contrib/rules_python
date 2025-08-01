# Python Gazelle plugin

:::{note}
The gazelle plugin docs are being migrated to our primary documentation on
ReadTheDocs. Please see https://rules-python.readthedocs.io/gazelle/docs/index.html.
:::


## Developer Notes

Gazelle extensions are written in Go.
See the gazelle documentation https://github.com/bazelbuild/bazel-gazelle/blob/master/extend.md
for more information on extending Gazelle.

If you add new Go dependencies to the plugin source code, you need to "tidy" the go.mod file.
After changing that file, run `go mod tidy` or `bazel run @go_sdk//:bin/go -- mod tidy`
to update the go.mod and go.sum files. Then run `bazel run //:gazelle_update_repos` to have gazelle
add the new dependenies to the deps.bzl file. The deps.bzl file is used as defined in our /WORKSPACE
to include the external repos Bazel loads Go dependencies from.

Then after editing Go code, run `bazel run //:gazelle` to generate/update the rules in the
BUILD.bazel files in our repo.
