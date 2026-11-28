(toolchains) The
{obj}`--@rules_python//python/config_settings:py_pbs_distribution` flag accepts
`debug` to select python-build-standalone debug (`Py_DEBUG`) runtimes, for
example from a release manifest added with
{obj}`python.override.add_runtime_manifest_urls`
([#4502](https://github.com/bazel-contrib/rules_python/issues/4502)).
