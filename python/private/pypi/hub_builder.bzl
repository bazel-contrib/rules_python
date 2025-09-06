"""A hub repository builder for incrementally building the hub configuration."""

def hub_builder(*, name, module_name):
    """Return a hub builder instance"""
    self = struct(
        name = name,
        module_name = module_name,
        python_versions = [],
        # buildifier: disable=uninitialized
        add = lambda *args, **kwargs: _add(self, *args, **kwargs),
        # buildifier: enable=uninitialized
    )
    return self

def _add(self, *, python_version):
    self.python_versions.append(python_version)
