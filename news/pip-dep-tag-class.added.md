(pypi) Added a `dep` tag class to the `pip` bzlmod extension. This allows
modules to declare abstract PyPI dependencies, ensuring target structures
exist in the unified hub, while allowing other modules to provide the
concrete implementation via `pip.parse`.
