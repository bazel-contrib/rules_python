# Ignores use declared names, and the terminal alias has an explicit override.
# gazelle:ignore pytester
pytest_plugins = ["pytester", "terminal", "monkeypatch"]
