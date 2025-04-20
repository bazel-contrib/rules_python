import os
import sys
import unittest


class VenvSitePackagesLibraryTest(unittest.TestCase):
    def test_imported_from_venv(self):
        self.assertNotEqual(sys.prefix, sys.base_prefix, "Not running under a venv")
        venv = sys.prefix

        from nspkg.subnspkg import alpha

        self.assertEqual(alpha.whoami, "alpha")
        self.assertEqual(alpha.__name__, "nspkg.subnspkg.alpha")

        self.assertTrue(
            alpha.__file__.startswith(sys.prefix),
            f"\nalpha was imported, not from within the venv.\n"
            + f"venv  : {venv}\n"
            + f"actual: {alpha.__file__}",
        )

        from nspkg.subnspkg import beta

        self.assertEqual(beta.whoami, "beta")
        self.assertEqual(beta.__name__, "nspkg.subnspkg.beta")
        self.assertTrue(
            beta.__file__.startswith(sys.prefix),
            f"\nbeta was imported, not from within the venv.\n"
            + f"venv  : {venv}\n"
            + f"actual: {beta.__file__}",
        )


if __name__ == "__main__":
    unittest.main()
