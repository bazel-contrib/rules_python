# Python Gazelle plugin

:::{note}
The gazelle plugin docs are being migrated to our primary documentation on
ReadTheDocs. Please see https://rules-python.readthedocs.io/gazelle/docs/index.html.
:::


### Libraries

Python source files are those ending in `.py` but not ending in `_test.py`.

First, we look for the nearest ancestor BUILD file starting from the folder
containing the Python source file.

In package generation mode, if there is no `py_library` in this BUILD file, one
is created using the package name as the target's name. This makes it the
default target in the package. Next, all source files are collected into the
`srcs` of the `py_library`.

In project generation mode, all source files in subdirectories (that don't have
BUILD files) are also collected.

In file generation mode, each file is given its own target.

Finally, the `import` statements in the source files are parsed, and
dependencies are added to the `deps` attribute.

### Unit Tests

A `py_test` target is added to the BUILD file when gazelle encounters
a file named `__test__.py`.
Often, Python unit test files are named with the suffix `_test`.
For example, if we had a folder that is a package named "foo" we could have a Python file named `foo_test.py`
and gazelle would create a `py_test` block for the file.

The following is an example of a `py_test` target that gazelle would add when
it encounters a file named `__test__.py`.

```starlark
py_test(
    name = "build_file_generation_test",
    srcs = ["__test__.py"],
    main = "__test__.py",
    deps = [":build_file_generation"],
)
```

You can control the naming convention for test targets by adding a gazelle directive named
`# gazelle:python_test_naming_convention`.  See the instructions in the section above that
covers directives.

### Binaries

When a `__main__.py` file is encountered, this indicates the entry point
of a Python program. A `py_binary` target will be created, named `[package]_bin`.

When no such entry point exists, Gazelle will look for a line like this in the top level in every module:

```python
if __name == "__main__":
```

Gazelle will create a `py_binary` target for every module with such a line, with
the target name the same as the module name.

If `python_generation_mode` is set to `file`, then instead of one `py_binary`
target per module, Gazelle will create one `py_binary` target for each file with
such a line, and the name of the target will match the name of the script.

Note that it's possible for another script to depend on a `py_binary` target and
import from the `py_binary`'s scripts. This can have possible negative effects on
Bazel analysis time and runfiles size compared to depending on a `py_library`
target. The simplest way to avoid these negative effects is to extract library
code into a separate script without a `main` line. Gazelle will then create a
`py_library` target for that library code, and other scripts can depend on that
`py_library` target.

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
