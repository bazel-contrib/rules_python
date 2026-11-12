(binaries/tests) The {obj}`stamp` attribute no longer transitions the
{flag}`--stamp` flag for the whole target, so dependencies of executables with
`stamp = 0` or `stamp = 1` are no longer built in a separate configuration.
