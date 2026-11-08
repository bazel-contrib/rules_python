(toolchains) Runtime manifests added with
{attr}`python.override.add_runtime_manifest_urls` or
{attr}`python.override.add_runtime_manifest_files` no longer select
python-build-standalone debug (`Py_DEBUG`) builds. Before, the `full`
distribution, and free-threaded runtimes of releases that ship only `full`
archives, could resolve to a `debug-full` archive whose layout the runtime
repository does not support.
