# Resolves proto imports

This test asserts that Gazelle can resolve imports from `py_proto_library` targets:

1.  Generates a dependency in the default case.
2.  Uses `gazelle:resolve` to generate dependencies.
3.  Uses `python_proto_naming_convention` to generate dependencies.
4.  Generates a correct dependency for a proto_library with multiple srcs.
