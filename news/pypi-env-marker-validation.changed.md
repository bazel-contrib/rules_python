(pypi) Invalid environment markers, e.g. with unbalanced parenthesis or unknown
variables, are now an error instead of being evaluated to true. The `<`, `<=`,
`>` and `>=` operators no longer compare the strings that are not versions
lexicographically: `<` and `>` are false and `<=` and `>=` check the equality,
as described in the
[dependency specifiers spec](https://packaging.python.org/en/latest/specifications/dependency-specifiers/#environment-markers).
