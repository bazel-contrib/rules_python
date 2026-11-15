pytest_plugins = ["plugins"]


def test_database(database):
    assert database == "database"
