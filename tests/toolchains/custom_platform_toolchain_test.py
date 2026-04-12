import sys
import unittest


class VerifyCustomPlatformToolchainTest(unittest.TestCase):

    def test_custom_platform_interpreter_used(self):
        # For lack of a better option, check the version. Identifying the
        self.assertEqual(
            "3.13.1",
            f"{sys.version_info.major}.{sys.version_info.minor}.{sys.version_info.micro}")


if __name__ == "__main__":
    unittest.main()
