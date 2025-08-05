# Python tags directive test

Tests the python_tags, python_library_tags, python_binary_tags, and python_test_tags directives.

These directives allow adding tags to generated Python targets:
- `python_tags` - Tags added to all Python targets
- `python_library_tags` - Tags specific to py_library targets
- `python_binary_tags` - Tags specific to py_binary targets
- `python_test_tags` - Tags specific to py_test targets

Tags from general and specific directives are combined.