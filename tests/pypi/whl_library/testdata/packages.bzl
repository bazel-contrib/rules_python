"""A list of packages that this logical testdata hub repo contains."""

# The values are the extras that are requested in the hub, the `pkg` package
# does not provide the `nope` extra.
packages = {
    "consumer": [],
    "optional_dep": [],
    "pkg": [
        "nope",
        "optional",
    ],
}
