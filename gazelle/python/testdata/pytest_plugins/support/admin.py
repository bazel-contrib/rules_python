import pytest


@pytest.fixture(name="admin")
def fixture_admin():
    return "database"
