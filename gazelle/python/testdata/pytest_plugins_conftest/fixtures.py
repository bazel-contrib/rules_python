import pytest


@pytest.fixture(name="database")
def fixture_database():
    return "database"
