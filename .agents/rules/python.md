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

