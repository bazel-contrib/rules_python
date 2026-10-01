# Root conftest plugins

Resolve a root conftest's plugin declaration and include its dependencies in the
consumer test. Unlike nested conftest plugin declarations, this layout can also
be collected by pytest from the workspace root.
