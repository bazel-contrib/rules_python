# Gazelle Plugin

[Gazelle][gazelle] is a build file generator for Bazel projects. It can
create new `BUILD` or `BUILD.bazel` files for a project that
follows language conventions and update existing build files to include new
sources, dependencies, and options.

[gazelle]: https://github.com/bazel-contrib/bazel-gazelle

Bazel may run Gazelle using the Gazelle rule, or Gazelle may be installed and run
as a command line tool.

The {gh-path}`gazelle` directory contains a plugin for Gazelle
that generates `BUILD` files content for Python code. When Gazelle is
run as a command line tool with this plugin, it embeds a Python interpreter
resolved during the plugin build. The behavior of the plugin is slightly
different with different version of the interpreter as the Python
`stdlib` changes with every minor version release. Distributors of Gazelle
binaries should, therefore, build a Gazelle binary for each OS+CPU
architecture+Minor Python version combination they are targeting.

:::{note}
These instructions are for when you use [bzlmod][bzlmod]. Please refer to
older documentation that includes instructions on how to use Gazelle
without using bzlmod as your dependency manager.
:::

[bzlmod]: https://bazel.build/external/module

Gazelle is non-destructive. It will try to leave your edits to `BUILD`
files alone, only making updates to `py_*` targets. However it **will
remove** dependencies that appear to be unused, so it's a good idea to check
in your work before running Gazelle so you can easily revert any changes it made.

The `rules_python` extension assumes some conventions about your Python code.
These are noted in the subsequent documents, and might require changes to your
existing code.

Note that the `gazelle` program has multiple commands. At present, only
the `update` command (the default) does anything for Python code.


## Pytest plugin dependencies

Gazelle resolves module-level `pytest_plugins` declarations as imports and adds
their modules to the generated target's dependencies. This lets tests reuse
pytest fixture plugins without duplicating dependencies in BUILD files:

```python
pytest_plugins = ["myapp.testing.database", "myapp.testing.http"]
```

Literal strings (including pytest's comma-separated string form), lists, and
tuples are supported, as are annotated assignments. Declarations in reusable
plugin modules are resolved too, providing transitive plugin dependencies.
Existing dependency resolution directives and `gazelle:ignore` annotations
apply to these module names just as they do to normal imports.

As with conditional imports, Gazelle includes all statically declared branches
and assignments; it does not evaluate Python control flow. Function-local and
class-local declarations are ignored. Dynamic values such as function calls,
variable references, list concatenation, comprehensions, and augmented
assignments are not evaluated. Bytes, f-strings, and named Unicode escapes are
also not evaluated. For unsupported declarations, use
{ref}`annotation-include-dep` to supply their dependencies explicitly.

Dependency generation does not change pytest's registration semantics: plugins
are available throughout a pytest invocation, and `pytest_plugins` in non-root
conftests is not supported by pytest.

:::{versionadded} 2.4.0
:::

```{toctree}
:maxdepth: 1
installation_and_usage
directives
annotations
development
```
