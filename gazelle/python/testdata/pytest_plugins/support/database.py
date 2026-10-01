import pytest

pytest_plugins = ("support.admin",)


@pytest.fixture(name="database")
def fixture_database(admin):
    return admin
