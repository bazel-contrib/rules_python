# Sibling imports disabled

This test case asserts that imports from sibling modules are NOT resolved as
absolute imports when the `python_resolve_sibling_imports` directive is
disabled. It covers 3 different types of imports in `pkg/unit_test.py`:

- `import a` - resolves to the root-level `a.py` instead of the sibling
  `pkg/a.py`
- `import test_util` - resolves to the root-level `test_util.py` instead of
  the sibling `pkg/test_util.py`
- `from b import run` - resolves to the root-level `b.py` instead of the
  sibling `pkg/b.py`

When sibling imports are disabled with
`# gazelle:python_resolve_sibling_imports false`, the imports remain as-is
and follow standard Python resolution rules where absolute imports can't refer
to sibling modules.
