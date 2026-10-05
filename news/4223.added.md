(pypi) The unified `@pypi` hub now generates a `requirements.bzl` with the same
API as a concrete hub's (`requirement`, `whl_requirement`, `data_requirement`,
`dist_info_requirement` and the `all_*` lists). A repo that renames its hub
away from the reserved `pypi` name keeps its
`load("@pypi//:requirements.bzl", "requirement")` users working, and the
returned labels route through
{obj}`--@rules_python//python/config_settings:venv`. The `all_*` lists name the
packages of the default hub.
