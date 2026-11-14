:::{default-domain} bzl
:::

# Circular dependencies

Sometimes PyPI packages contain dependency cycles. For instance, a particular
version of `sphinx` (this is no longer the case in the latest version as of
2024-06-02) depends on `sphinxcontrib-serializinghtml`. When using them as
`requirement()`s, ala

```starlark
py_binary(
    name = "doctool",
    ...
    deps = [
        requirement("sphinx"),
    ],
)
```

Bazel will protest because it doesn't support cycles in the build graph --

```
ERROR: .../external/pypi_sphinxcontrib_serializinghtml/BUILD.bazel:44:6: in alias rule @pypi_sphinxcontrib_serializinghtml//:pkg: cycle in dependency graph:
    //:doctool (...)
    @pypi//sphinxcontrib_serializinghtml:pkg (...)
.-> @pypi_sphinxcontrib_serializinghtml//:pkg (...)
|   @pypi_sphinxcontrib_serializinghtml//:_pkg (...)
|   @pypi_sphinx//:pkg (...)
|   @pypi_sphinx//:_pkg (...)
`-- @pypi_sphinxcontrib_serializinghtml//:pkg (...)
```

The `experimental_requirement_cycles` attribute allows you to work around these
issues by specifying groups of packages which form cycles. `pip_parse` will
transparently fix the cycles for you and provide the cyclic dependencies
simultaneously.

```starlark
    ...
    experimental_requirement_cycles = {
        "sphinx": [
            "sphinx",
            "sphinxcontrib-serializinghtml",
        ]
    },
)
```

`pip_parse` supports fixing multiple cycles simultaneously, however, cycles must
be distinct. `apache-airflow`, for instance, has dependency cycles with a number
of its optional dependencies, which means those optional dependencies must all
be a part of the `airflow` cycle. For instance:

```starlark
    ...
    experimental_requirement_cycles = {
        "airflow": [
            "apache-airflow",
            "apache-airflow-providers-common-sql",
            "apache-airflow-providers-postgres",
            "apache-airflow-providers-sqlite",
        ]
    }
)
```

Each extra of a package has its own target, so a cycle that goes through an
extra back to the package without extras, e.g. `foo[bar]` depending on `baz`
which depends on `foo`, is not a cycle in Bazel and does not need a group. If
the cycle includes the extra itself, e.g. `baz` depends on `foo[bar]`, then
only the extra needs to be a member of the group:

```starlark
    ...
    experimental_requirement_cycles = {
        "foo": [
            "foo[bar]",
            "baz",
        ]
    }
)
```

Only the targets of the members, `@pypi//foo:[bar]` and `@pypi//baz`, are
then part of the group and the other targets of `foo`, e.g. `@pypi//foo:[]`,
can be used without the group. The `whl` targets do not use the extras, so
only the packages without extras are part of the group for the `whl` targets.

:::{versionadded} VERSION_NEXT_FEATURE
Support for the extras as members of the groups.
:::

Alternatively, one could resolve the cycle by removing one leg of it.

For example, while `apache-airflow-providers-sqlite` is "baked into" the Airflow
package, `apache-airflow-providers-postgres` is not and is an optional feature.
Rather than listing `apache-airflow[postgres]` in your `requirements.txt`, which
would expose a cycle via the extra, one could either _manually_ depend on
`apache-airflow` and `apache-airflow-providers-postgres` separately as
requirements. Bazel rules which need only `apache-airflow` can take it as a
dependency, and rules which explicitly want to mix in
`apache-airflow-providers-postgres` now can.

Alternatively, one could use `rules_python`'s patching features to remove one
leg of the dependency manually, for instance, by making
`apache-airflow-providers-postgres` not explicitly depend on `apache-airflow` or
perhaps `apache-airflow-providers-common-sql`.
