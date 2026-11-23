# Pyrefly misses markupsafe._speedups because venvs_site_packages = "yes" omits
# external repo prefixes from PyInfo.imports.
import markupsafe._speedups  # pyrefly: ignore[missing-import]

print(f"native ext: {markupsafe._speedups}")
