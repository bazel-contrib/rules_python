"""Library-like rule to collect docs."""

load("//private:sphinx_docs_library_macro.bzl", _sphinx_docs_library = "sphinx_docs_library")

sphinx_docs_library = _sphinx_docs_library
