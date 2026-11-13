(pypi) The default `_freethreaded` {obj}`pip.default` platforms now select the
`abi3t` wheels that use the stable ABI for the free-threaded builds as specified
in [PEP 803](https://peps.python.org/pep-0803/). The version-specific `cp3xt`
wheels are still preferred over `abi3t` wheels.
