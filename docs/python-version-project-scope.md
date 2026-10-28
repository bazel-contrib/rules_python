# Python version project scoping

A Python binding and its build tools need a selected interpreter version; a pure
C++ or Rust dependency often does not. With a fixed command-line Python version,
project scoping lets binaries transition to different Python versions while their
native dependencies return to the same invocation baseline.

This is an opt-in for the root module; tags in dependency modules are ignored,
so a library can use it locally without imposing policy on its consumers.
Existing behavior is unchanged when the tag is absent.

```starlark
# MODULE.bazel
config = use_extension("@rules_python//python/extensions:config.bzl", "config")
config.python_version_scope(scope = "project")
```

Create `PROJECT.scl` in the root module:

```starlark
project = {
    "active_directories": {
        "default": [
            "//bindings",
            "@@rules_python+",
        ],
    },
}
```

Project scope requires Bazel 9.2 or later: older versions can reset the selected
version on exec transitions even for owned tools
([upstream fix](https://github.com/bazelbuild/bazel/issues/28320)). Enable
`--experimental_enable_scl_dialect` on Bazel 9. The integration fixture checks target and exec version propagation. Repository names in `active_directories` are canonical names;
check the names in your resolved module graph when using another Bazel version.
The flag's project definition delegates to the root `//:PROJECT.scl`. That file
can itself redirect to another project definition with Bazel's `actual` field.

The example owns only `//bindings` and this ruleset. Extend it to cover **all**
Python-sensitive consumers, including bindings, interpreter/header repositories,
version-sensitive generators, toolchain targets, and other Python rulesets in a
mixed build. Every dependency path must stay inside the owned boundary until it
reaches Python-independent code. Scope does not infer ownership from dependencies
and cannot detect an omitted Python consumer; an incomplete boundary can select
the wrong interpreter. Owned exec tools retain the selected version too.

Use a fixed `--@rules_python//python/config_settings:python_version=3.10` baseline and terminal targets that transition
to their required versions. Outside the boundary, Bazel restores that invocation
baseline, **not** a separate declared default. Separate invocations with different
command-line baselines can still produce different native configurations.

This scopes only the Python version selector. It does not trim ABI, platform,
freethreading, build-script environment, or other settings. When both Python
rulesets' version flags are transitioned, opt into compatible ownership for both.

See [Bazel's project-scoped flags example](https://github.com/gregestren/snippets/tree/master/project_scoped_flags)
and the [configurability roadmap](https://bazel.build/about/roadmap#configurability).
