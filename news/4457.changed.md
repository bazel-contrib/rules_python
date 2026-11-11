(toolchains) With WORKSPACE, `python_register_toolchains(register_coverage_tool = True)`
uses the same `coverage` wheels as bzlmod, which are locked in the `uv.lock`
file of `rules_python`, without any changes to the `WORKSPACE` file. The
coverage tool is now available for all of the platforms of the hermetic
toolchains.
