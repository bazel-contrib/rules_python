"""A list of packages that this logical testdata hub repo contains."""

# The values are the extras that are requested in the hub, the `pkg` package
# does not provide the `nope` extra. The `optional` extra of `pkg` is not
# requested in the hub, but the `consumer` package depends on it.
packages = {
    "consumer": [],
    "optional_dep": [],
    "pkg": [
        "nope",
    ],
}
