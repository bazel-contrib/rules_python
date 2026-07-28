(common-deps-with-multiple-pypi-versions)=
# How to use a common set of dependencies with multiple PyPI versions

In this guide, we show how to handle a situation common to monorepos that
extensively share code: How do multiple binaries utilize distinct requirements
files while pulling from shared internal libraries, without requiring
manually-maintained `select()` logic inside dependency targets?

Stated as code, consider this example:

```bzl
# When building bin_alpha, requests and more_itertools should resolve
# from requirements_alpha.txt
py_binary(
    name = "bin_alpha",
    deps = [
        "@pypi//requests",
        ":common",
    ],
)

# When building bin_beta, requests and more_itertools should resolve
# from requirements_beta.txt
py_binary(
    name = "bin_beta",
    deps = [
        "@pypi//requests",
        ":common",
    ],
)

# Transitive dependencies like more_itertools are requested here, but
# must automatically match whichever dependency track is active for the binary.
py_library(
    name = "common",
    deps = ["@pypi//more_itertools"],
)
```

## Defining dependency tracks via custom platforms

The solution involves defining custom "platforms" mapped to separate
dependency tracks inside `MODULE.bazel`. Using custom platforms via
{obj}`pip.default` and associating requirements files to them through the
`requirements_by_platform` attribute on {obj}`pip.parse` instructs
`rules_python` to generate `select()` logic behind a unified hub.

Binaries configure their execution requirements by forcing flag transition
attributes using custom build setting flags.

In this example, we define custom string flag named `//:pypi_hub`, setup
distinct custom platforms for `"alpha"` and `"beta"` profiles, and register
associated requirements lock files grouped inside the `@pypi` hub.

```starlark
# File: MODULE.bazel

rules_python_config = use_extension(
    "@rules_python//python/extensions:config.bzl",
    "config",
)
rules_python_config.add_transition_setting(
    setting = "//:pypi_hub",
)

pip = use_extension("@rules_python//python/extensions:pip.bzl", "pip")

pip.default(
    platform = "alpha",
    config_settings = ["@//:is_pypi_alpha"],
)

pip.default(
    platform = "beta",
    config_settings = ["@//:is_pypi_beta"],
)

pip.parse(
    hub_name = "pypi",
    python_version = "3.14",
    requirements_by_platform = {
        "//:requirements_alpha.txt": "alpha",
        "//:requirements_beta.txt": "beta",
    },
)

use_repo(pip, "pypi")
```

```starlark
# File: BUILD.bazel

load("@bazel_skylib//rules:common_settings.bzl", "string_flag")

string_flag(
    name = "pypi_hub",
    build_setting_default = "none",
)

config_setting(
    name = "is_pypi_alpha",
    flag_values = {"//:pypi_hub": "alpha"},
)

config_setting(
    name = "is_pypi_beta",
    flag_values = {"//:pypi_hub": "beta"},
)

py_binary(
    name = "bin_alpha",
    srcs = ["bin_alpha.py"],
    config_settings = {
        "//:pypi_hub": "alpha",
    },
    deps = [
        "@pypi//requests",
        ":common",
    ],
)

py_binary(
    name = "bin_beta",
    srcs = ["bin_beta.py"],
    config_settings = {
        "//:pypi_hub": "beta",
    },
    deps = [
        "@pypi//requests",
        ":common",
    ],
)

py_library(
    name = "common",
    deps = ["@pypi//more_itertools"],
)
```

When building `bin_alpha` or `bin_beta`, they set `//:pypi_hub` via target
transitions. The generated aliased dependencies inside the `@pypi` hub will
evaluate that Bazel configuration, automatically delivering corresponding
Python wheels from targeted lock files.

