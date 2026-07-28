# Sphinx Stardoc Test

This is a set of documents to test the sphinx_stardoc extension.

To build and view these docs, run:

```
bazel run //tests/sphinx_stardoc:docs.serve
```

This will build the docs and start an HTTP server where they can be viewed.

To aid the edit/debug cycle, `ibazel` can be used to automatically rebuild
the HTML:

```
ibazel build //tests/sphinx_stardoc:docs
```

:::{toctree}
:hidden:
:glob:

**
genindex
:::
