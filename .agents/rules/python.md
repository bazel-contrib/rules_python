# Python Conventions

## pytest
* Register helper fixtures using `pytest_plugins = ["<module_path>"]`.
* Name fixture functions with `fixture_` prefix and pass public name via
  `@pytest.fixture(name="foo")`.

## CLI & Arguments
* Use direct attribute access (e.g. `args.foo`) on `argparse.Namespace` with
  well-defined shapes. Avoid defensive `getattr()`.

## TypedDict
* **External Objects**: When defining a `TypedDict` for an external object,
  link to its definition in the docstring.

## Type Checking & Annotations
* **In-file disables vs target skipping**: Prefer `# pyrefly: ignore[<error-code>]`
  (e.g. `[missing-import]`) over `tags = ["no-pyrefly"]`.
* **No blanket ignores**: NEVER use bare `# type: ignore` or literal
  `# type: ignore[...]`. Use error-specific ignores instead.
* **Type assertions**: When adding assertions for type narrowing, add an
  end-of-line comment: `assert foo is not None  # type assert`.
* **Consent for `Any`**: Require user consent before changing type annotations
  to `Any`.

## Delegating Functions
* Module-level functions delegating to class methods should have a docstring
  referring to the class method (e.g. `"""Refer to \`Class.method\`."""`).


