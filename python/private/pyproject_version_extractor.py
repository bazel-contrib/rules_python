#!/usr/bin/env python3
"""Extract Python version from pyproject.toml."""

import re
import sys

try:
    import tomllib as toml
except ImportError:
    try:
        import tomli as toml
    except ImportError:
        raise SystemExit(
            "need tomllib (python >=3.11) or tomli installed on host python"
        )


def validate_and_extract(pyproject_path):
    """Validate format and extract version."""
    with open(pyproject_path, "rb") as f:
        data = toml.load(f)

    version = data["project"]["requires-python"]

    if not version.startswith("=="):
        sys.exit(f"requires-python must use '==' for exact version, got: {version}")

    bare_version = version[2:].strip()

    if not re.match(r"^\d+\.\d+\.\d+$", bare_version):
        sys.exit(f"requires-python must be in X.Y.Z format, got: {bare_version}")

    return bare_version


def main():
    if len(sys.argv) < 2:
        sys.exit("Usage: pyproject_version_extractor.py <pyproject.toml>")

    version = validate_and_extract(sys.argv[1])
    print(version)


if __name__ == "__main__":
    main()
