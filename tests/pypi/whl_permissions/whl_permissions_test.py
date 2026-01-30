"""Test that wheels with incorrect file permissions can be extracted and used.

Some wheels have files without read permissions set, which causes errors
when Bazel tries to read them during extraction. This test verifies that
the permission-fixing logic in whl_extract.bzl handles these cases correctly.
"""

import unittest


class WhlPermissionsTest(unittest.TestCase):
    def test_can_import_from_bad_perms_wheel(self):
        """Test that we can import and use code from a wheel with bad permissions."""
        # If the permissions weren't fixed, the whl_library rule would have
        # failed when trying to read __init__.py during namespace package detection.
        import bad_perms_pkg

        # Verify we can call functions from the module
        result = bad_perms_pkg.test()
        self.assertEqual(result, "hello")

    def test_can_import_module_from_bad_perms_wheel(self):
        """Test that we can import submodules from a wheel with bad permissions."""
        from bad_perms_pkg import module

        # Verify we can access module contents
        self.assertEqual(module.VALUE, 42)


if __name__ == '__main__':
    unittest.main()
