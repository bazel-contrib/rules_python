# Directive: `python_resolve_pytest_plugins`

This test case asserts that the `# gazelle:python_resolve_pytest_plugins`
directive controls whether module-level `pytest_plugins` declarations are
resolved into dependencies, and that child packages inherit the value:

+ The root level does not set the directive (it defaults to true), so
  `enabled_test` depends on the `plugins` module it declares.
+ `disabled/` sets the directive to false. `disabled_test` keeps its ordinary
  `import pytest` dependency, but none of its `pytest_plugins` entries are
  added, including an unresolvable one that would otherwise fail validation.
+ `disabled/reenabled/` sets the directive back to true.
