(pypi) The dependencies that have markers which are satisfied by the
requested extra irrespective of the platform, e.g.
`sys_platform == "linux" or extra == "foo"`, are now included unconditionally
instead of through a `select` that is always true.
