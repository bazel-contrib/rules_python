# Pytest plugin dependencies

Also covers pytest built-in aliases (including stdlib-name collisions), alias
ignores and overrides, and ordinary imports sharing a plugin alias's name.

Resolve literal plugin declarations in tests and reusable plugin
modules. Verify prerequisite chains, external modules, duplicate imports,
resolution overrides, dependency ignores, mixed dynamic entries, and unrelated
sibling test isolation. External and ignored module names are resolution inputs;
this fixture is not intended to execute pytest.
