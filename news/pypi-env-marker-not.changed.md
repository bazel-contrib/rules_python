(pypi) The `not` operator, e.g. `not os_name == "nt"`, is no longer accepted in
the environment markers, because it is not in the
[dependency specifiers spec](https://packaging.python.org/en/latest/specifications/dependency-specifiers/#environment-markers).
Use the inverse operator instead, e.g. `os_name != "nt"`.
