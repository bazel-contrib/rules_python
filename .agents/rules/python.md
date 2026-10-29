---
trigger: glob
description: Python coding, typing, CLI, and pytest conventions
globs: "*.py,*.sh"
---

# Python Conventions

## pytest
* Register helper fixtures using `pytest_plugins = ["<module_path>"]`.
* Name fixture functions with `fixture_` prefix and pass public name via
  `@pytest.fixture(name="foo")`.

## CLI & Arguments
* Use direct attribute access (e.g. `args.foo`) on `argparse.Namespace` with
  well-defined shapes. Avoid defensive `getattr()`.
* Assume caller-guaranteed preconditions hold (e.g., input directories exist
  and contain files). Do not add silent no-op guards (`if path.is_dir():` or
  `if not path.is_file(): continue`) that mask broken invocations.
* Factor non-trivial scripts (such as multi-line Python or shell logic) into
  standalone files (e.g. `.py` or `.sh` files) instead of inlining them via
  heredocs (`<< 'EOF'`) or `-c` flags (`python3 -c`, `bash -c`).
* **Directly Executable Scripts**: Scripts executed directly (outside a
  `py_binary` rule) must have `chmod +x` (mode `100755`) and a
  `#!/usr/bin/env python3` shebang.
* Do not repeat default values in CLI flag `help` strings when the parser
  displays defaults automatically.
* Include a `Usage:` example and input file format description in CLI module
  docstrings.

## API Minimalism & Module State
* Pass dependencies explicitly; avoid implicit optionals that auto-load state or
  magical global state. Do not return mutable internal state.
* Assume the supported execution environment. Do not add `ImportError`
  fallbacks or `sys.path` probing unless direct invocation outside Bazel is
  required by an external caller constraint and justified in a comment or PR
  description.
* Prefix private module-level constants and tables with `_`.
* Use direct attribute syntax (`obj.attr`) instead of `getattr`/`setattr` for
  static attribute names.

## Interface & ABC Docstrings
* In abstract base class / interface methods, always document `Args:`,
  `Returns:`, and all custom exceptions raised under `Raises:`.

## Exception Handling
* Inherit custom exceptions from `Exception`, not `RuntimeError`.
* Let errors bubble up from utility functions instead of printing and returning
  failure sentinels or catching and re-wrapping into caller-specific exception
  classes.
* Use `e.add_note(...)` to attach context to an exception and plain `raise` when
  re-raising.
* Do not place redundant `return` statements after `sys.exit(...)`.

## Unit Testing
* Use real temporary files (`tmp_path` or `tempfile`) instead of mocking file IO
  or `pathlib.Path`.
* Use `unittest.mock.patch` (and `mock.create_autospec(..., instance=True)` over
  bare `Mock()`/`MagicMock()`) instead of manual state save/restore, and avoid
  over-mocking the unit under test.
* Call `main(args)` directly in tests instead of mutating `sys.argv`, and test
  `sys.exit` with `pytest.raises(SystemExit)` / `assertRaises(SystemExit)`
  instead of mocking `sys.exit`.
* Do not prefix test method names with redundant target names (e.g., use
  `test_success_directory` instead of `test_main_success_directory`).
* Factor repeated assertion blocks into `_assert_*` helpers, and assert against
  literal expected strings in formatting/transformation tests rather than
  duplicating production logic.

## Subprocess
* Demarcate captured stdout/stderr in exceptions with 20 `=` characters:
  `==================== STDOUT BEGIN ====================` /
  `==================== STDOUT END ====================` (same for STDERR).

## TypedDict
* **External Objects**: When defining a `TypedDict` for an external object,
  link to its definition in the docstring.

## Type Checking & Annotations
* **Version differences**: Guard version-specific arguments or APIs with runtime
  checks (e.g. `if sys.version_info >= (3, 13):`) instead of
  `# pyrefly: ignore[...]` comments.
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

## Context Managers
* Implement temporary state changes (e.g., `Git.checkout()`, `os.chdir()`) as
  context managers that restore prior state on exit.

## Formatting
* Do not line-break long string literals (such as URLs or hashes) to fit line
  length limits; allow them to exceed the limit.
