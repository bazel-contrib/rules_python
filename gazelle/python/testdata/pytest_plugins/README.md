# Pytest plugin dependencies

Resolve literal plugin declarations in tests and reusable plugin
modules. Verify prerequisite chains, external modules, duplicate imports,
resolution overrides, dependency ignores, mixed dynamic entries, and unrelated
sibling test isolation. External and ignored module names are resolution inputs;
this fixture is not intended to execute pytest.
