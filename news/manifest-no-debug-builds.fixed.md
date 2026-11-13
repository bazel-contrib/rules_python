(toolchains) Runtime manifests added with
{obj}`python.override.add_runtime_manifest_urls` or
{obj}`python.override.add_runtime_manifest_files` now prefer non-debug
python-build-standalone builds over debug (`Py_DEBUG`) builds
([#4442](https://github.com/bazel-contrib/rules_python/issues/4442)).
