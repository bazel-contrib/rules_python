Fixed loading of the root `@rules_python//` package when `rules_python` is
used as an external repository that includes the `gazelle` directory, e.g.
via `git_override` or `local_path_override`. Previously, the internal
`//:gazelle_downloader_configs` target used labels that crossed into the
`//gazelle` package and failed loading of every target in the root package.
