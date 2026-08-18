# Python Conventions

## pytest
* Register helper fixtures using `pytest_plugins = ["<module_path>"]`.
* Name fixture functions with `fixture_` prefix and pass public name via
  `@pytest.fixture(name="foo")`.

## CLI & Arguments
* Use direct attribute access (e.g. `args.foo`) on `argparse.Namespace` with
  well-defined shapes. Avoid defensive `getattr()`.

## Interface & ABC Docstrings
* In abstract base class / interface methods, always document `Args:`,
  `Returns:`, and all custom exceptions raised under `Raises:`.

## Exception Handling
* Inherit custom exceptions from `Exception`, not `RuntimeError`.

## Subprocess
* Demarcate captured stdout/stderr in exceptions with 20 `=` characters:
  `==================== STDOUT BEGIN ====================` /
  `==================== STDOUT END ====================` (same for STDERR).

## TypedDict
* **External Objects**: When defining a `TypedDict` for an external object,
  link to its definition in the docstring.

## Type Checking & Annotations
* **`importlib.metadata` `PackagePath`**: `f.locate()` is typed as `PathLike`.
  Wrap with `pathlib.Path(f.locate())` to call `.exists()`, `.is_file()`, etc.
* **In-file disables vs target skipping**: Prefer
  `# pyrefly: ignore[<error-code>]` (e.g. `[missing-import]`) over
  `tags = ["no-pyrefly"]`.
* **No blanket ignores**: NEVER use bare `# type: ignore` or literal
  `# type: ignore[...]`. Use error-specific ignores instead.
* **Ignore comments**: When adding `# pyrefly: ignore[...]` or type
  suppressions, add an explanatory comment indicating why it is suppressed.
* **Type assertions**: When adding assertions for type narrowing, add an
  end-of-line comment: `assert foo is not None  # type assert`.
* **Consent for `Any`**: Require user consent before changing type annotations
  to `Any`.
* **Union syntax (`X | None`)**: Use `X | None` instead of `typing.Optional[X]`.
  Add `from __future__ import annotations` if necessary.
* **Collections generics**: Use `collections.abc` (e.g., `Sequence`, `Iterable`,
  `Iterator`, `Callable`, `Mapping`) and builtin generics (`list`, `dict`,
  `tuple`, `set`) instead of `typing.XXX` collection types.

## Runfiles
* **Fail-fast creation**: Prefer `runfiles.CreateOrRaise()` over
  `runfiles.Create()` + `assert`.
* **Path navigation**: Prefer `rf.root() / "<repo>/<path>"` over `Rlocation()`;
  use `.glob()` on `runfiles.Path` instead of multi-root fallback loops.

## Delegating Functions
* Module-level functions delegating to class methods should have a docstring
  referring to the class method (e.g. `"""Refer to \`Class.method\`."""`).


