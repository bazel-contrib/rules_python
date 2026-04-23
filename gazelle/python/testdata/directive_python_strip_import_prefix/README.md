Test that # gazelle:python_strip_import_prefix strips a path segment from the
filesystem path before computing Python import specs.

This is useful for src-layout packages where a "src/" directory is not part of
the Python import path (e.g. pyproject.toml: packages = ["src/mylib"]).

Without the directive, gazelle would index the library as "src.mylib" and the
consumer's import of "mylib" would fail to resolve.
