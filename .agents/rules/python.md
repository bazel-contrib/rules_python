# Python Conventions

## pytest
* **Fixture Registration via `pytest_plugins`**: When registering pytest helper
  modules in test files, use `pytest_plugins = ["<module_path>"]`.
* **Fixture Naming Conventions**: Name fixture functions with a `fixture_`
  prefix (e.g. `def fixture_foo():`), and pass the public fixture name using the
  `name` parameter in `@pytest.fixture(name="foo")`.

## TypedDict
* **External Objects**: When defining a `TypedDict` for an external object,
  link to its definition in the docstring.
