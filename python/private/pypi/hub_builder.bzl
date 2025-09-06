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
    if python_version in self.python_versions:
        fail((
            "Duplicate pip python version '{version}' for hub " +
            "'{hub}' in module '{module}': the Python versions " +
            "used for a hub must be unique"
        ).format(
            hub = self.name,
            module = self.module_name,
            version = python_version,
        ))

    self.python_versions.append(python_version)
