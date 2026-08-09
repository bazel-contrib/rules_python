# Python Conventions

## pytest
* Register helper fixtures using `pytest_plugins = ["<module_path>"]`.
* Name fixture functions with `fixture_` prefix and pass public name via
  `@pytest.fixture(name="foo")`.

## CLI & Arguments
* Use direct attribute access (e.g. `args.foo`) on `argparse.Namespace` with
  well-defined shapes. Avoid defensive `getattr()`.

## Type Checking & Annotations
* **Target skipping vs in-file disables**: Prefer disabling specific errors in
  source files (e.g. `# type: ignore[...]` / `# pyrefly: ignore[...]`) over
  disabling type checking on targets (e.g. `tags = ["no-pyrefly"]`).
* **Type assertions**: When adding assertions for type narrowing, add an
  end-of-line comment: `assert foo is not None  # type assert`.
* **Consent for `Any`**: Require user consent before changing type annotations
  to `Any`.


