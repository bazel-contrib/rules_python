#!/usr/bin/env python3
"""Build a test wheel with files that have no read permissions.

This simulates wheels that are created with incorrect file permissions,
which can cause extraction failures when Bazel tries to read the files.
"""

import sys
import zipfile
from pathlib import Path


def create_bad_perms_wheel(output_path: str):
    """Create a wheel file with files that have no read permissions."""
    with zipfile.ZipFile(output_path, 'w', zipfile.ZIP_DEFLATED) as whl:
        # Add __init__.py with no read permissions (mode 000)
        info = zipfile.ZipInfo('bad_perms_pkg/__init__.py')
        info.external_attr = 0o000 << 16  # No permissions
        whl.writestr(info, 'def test():\n    return "hello"\n')

        # Add a module file with no read permissions
        module_info = zipfile.ZipInfo('bad_perms_pkg/module.py')
        module_info.external_attr = 0o000 << 16  # No permissions
        whl.writestr(module_info, 'VALUE = 42\n')

        # Add METADATA with no read permissions
        metadata = zipfile.ZipInfo('bad_perms_pkg-1.0.dist-info/METADATA')
        metadata.external_attr = 0o000 << 16  # No permissions
        whl.writestr(metadata, '''Metadata-Version: 2.1
Name: bad-perms-pkg
Version: 1.0
Summary: Test package with bad file permissions
Author: Test
License: Apache-2.0
''')

        # Add WHEEL with normal permissions (so the wheel can be opened)
        wheel_info = zipfile.ZipInfo('bad_perms_pkg-1.0.dist-info/WHEEL')
        wheel_info.external_attr = 0o644 << 16
        whl.writestr(wheel_info, '''Wheel-Version: 1.0
Generator: test
Root-Is-Purelib: true
Tag: py3-none-any
''')

        # Add RECORD with normal permissions
        record = zipfile.ZipInfo('bad_perms_pkg-1.0.dist-info/RECORD')
        record.external_attr = 0o644 << 16
        whl.writestr(record, '''bad_perms_pkg/__init__.py,,
bad_perms_pkg/module.py,,
bad_perms_pkg-1.0.dist-info/METADATA,,
bad_perms_pkg-1.0.dist-info/WHEEL,,
bad_perms_pkg-1.0.dist-info/RECORD,,
''')


if __name__ == '__main__':
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <output_wheel_path>", file=sys.stderr)
        sys.exit(1)

    output_path = sys.argv[1]
    create_bad_perms_wheel(output_path)
    print(f"Created wheel with bad permissions: {output_path}")
