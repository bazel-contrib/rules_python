import pytest

plugin_name = "support.admin"
additional_plugins = []

# gazelle:ignore nonexistent.plugin
pytest_plugins = [
    "support.database",
    "support.database",  # Duplicate declarations resolve to one dependency.
    "pytest",
    "external_plugin",
    "aliased_plugin",
    "ignored_plugin",
    "nonexistent.plugin",
    # Dynamic entries do not hide the statically known dependencies above.
    plugin_name,
    *additional_plugins,
]


def test_database(database):
    assert database == "database"
