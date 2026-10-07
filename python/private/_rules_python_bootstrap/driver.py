"""Load the declared private package without using application import paths."""

import sys

if not getattr(sys.flags, "safe_path", False) and not sys.flags.isolated and sys.path:
    del sys.path[0]

import importlib.machinery
import importlib.util
import os

spec = importlib.machinery.PathFinder.find_spec(
    "_rules_python_bootstrap", [os.path.dirname(os.path.dirname(__file__))]
)
package = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = package
spec.loader.exec_module(package)

if __name__ == "__main__":
    from _rules_python_bootstrap import entry

    if sys.argv[1] == "directory":
        sys.exit(entry.shell_directory_main(sys.argv[2:]))
    elif sys.argv[1] == "prepare-archive":
        entry.prepare_archive(sys.argv[2], sys.argv[3], cached=sys.argv[4] == "1")
    else:
        raise ValueError("Unknown bootstrap entry: " + sys.argv[1])
