import pytest

pytest_plugins = ["plugins", "pytester", "not_a_real_plugin"]


def test_database(database):
    assert database == "database"
