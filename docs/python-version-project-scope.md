# Python version project scoping

A Python binding and its build tools need the selected interpreter version; a
C++ or Rust library underneath the binding usually does not. Bazel's project
scope lets the root module name the packages that own the
`//python/config_settings:python_version` flag. Targets outside them see the
version given on the command line, so binaries transitioned to different Python
versions share one configuration of their Python-independent native
dependencies.

Project scope is off by default, and only the root module can enable it. Tags in
dependency modules are ignored, so a library can use it in its own builds
without imposing a policy on its consumers.

```starlark
# MODULE.bazel
config = use_extension("@rules_python//python/extensions:config.bzl", "config")
config.python_version_scope(scope = "project")
```

`scope` accepts:

* `"universal"` (the default): the version reaches every target, including exec
  tools such as the precompiler.
* `"project"`: the root module's `//:PROJECT.scl` decides which targets keep the
  version.

Project scope requires Bazel 9.2 or later. Older releases drop project-scoped
flags on exec transitions, so even owned exec tools would lose the version
([bazelbuild/bazel#28320](https://github.com/bazelbuild/bazel/issues/28320)).
The extension fails on older versions.

## Ownership

Under project scope, `//python/config_settings:python_version` is an alias to
a flag in rules_python's generated configuration repository. That repository's
`PROJECT.scl` forwards to the root module's `//:PROJECT.scl` with Bazel's
`actual` field, which may itself redirect with `actual`. Without the tag nothing
forwards there, so other builds don't need a root `PROJECT.scl`. List every
package that must see the selected version in `active_directories`:

```starlark
# PROJECT.scl
project = {
    "active_directories": {
        "default": [
            "//bindings",
            "@@rules_python+",
        ],
    },
}
```

Repositories are listed by canonical name. `bazel mod dump_repo_mapping ""`
prints the canonical names visible to the root module.

The example owns only `//bindings` and rules_python itself. A real project must
also own every other Python-sensitive target: interpreter and header
repositories, toolchains, version-sensitive generators, and any alias or
wrapper in between. Every dependency path from a transitioned target must stay
inside the owned packages until it reaches Python-independent code. Owned exec
tools keep the selected version. Bazel does not infer ownership from
dependencies and cannot detect an omitted consumer: such a target sees the
command-line version and can select the wrong interpreter.

If you also use aspect_rules_py, its terminals set this flag as well as their
own `@aspect_rules_py//py:python_version`. Scope both flags and own both
rulesets' repositories, or native dependencies still get one configuration per
Python version.

## Command-line baseline

Pass a fixed `--@rules_python//python/config_settings:python_version=<version>`
and let binaries select their versions with transitions, for example through
`python_version` attributes. Outside the owned packages, Bazel restores that
command-line value, not the flag's declared default. Invocations with different
command-line versions therefore still build native dependencies in different
configurations.

## Limitations

Only the Python version flag is scoped. ABI, platform, free-threading,
build-script environment, and other settings are unaffected.

See Bazel's
[project-scoped flags example](https://github.com/gregestren/snippets/tree/master/project_scoped_flags)
and the [configurability roadmap](https://bazel.build/about/roadmap#configurability).
