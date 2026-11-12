(pypi) Wheels patched with `pip.override` are repacked with Bazel's zipper when it is available, so hosts without a `zip` binary no longer fail. The repacked wheel also has fixed timestamps.
