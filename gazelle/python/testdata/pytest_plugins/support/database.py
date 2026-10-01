import pytest

pytest_plugins = (
    # A comment before a parenthesized value must not hide its dependency.
    ("support.admin",)
)


@pytest.fixture(name="database")
def fixture_database(admin):
    return admin
