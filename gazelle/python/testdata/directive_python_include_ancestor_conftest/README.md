# Directive: `python_include_ancestor_conftest`

This test case asserts that the `# gazelle:python_include_ancestor_conftest`
directive correctly includes or excludes ancestor contest targets in `py_test`
target dependencies.

The test also asserts that the directive can be applied at any level and that
child levels will inherit the value:

+ The root level does not set the directive (it defaults to True).
+ The next level, `one/`, inherits that value.
+ The next level, `one/two/`, sets the directive to False and thus the
  `py_test` target only includes the sibling `:conftest` target.
+ The final level, `one/two/three`, sets the directive back to True and thus
  the `py_test` target includes a total of 4 `conftest` targets.

See [Issue #3595](https://github.com/bazel-contrib/rules_python/issues/3595).
