(rules) Fixed venv output paths for `py_binary` and `py_test` targets whose
names contain path separators so distinct targets with the same basename no
longer share the same venv output directory.
