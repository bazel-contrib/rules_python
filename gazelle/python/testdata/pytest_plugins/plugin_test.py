import pytest

# gazelle:ignore nonexistent.plugin
pytest_plugins = [
    "support.database",
    "support.database",  # Duplicate declarations resolve to one dependency.
    "pytest",
    "external_plugin",
    "aliased_plugin",
    "ignored_plugin",
    "nonexistent.plugin",
]


def test_database(database):
    assert database == "database"
