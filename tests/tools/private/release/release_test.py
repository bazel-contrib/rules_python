import unittest

from tools.private.release import release as releaser


class ReleaseCLITest(unittest.TestCase):
    def test_valid_version(self):
        # These should not raise an exception
        releaser.create_parser().parse_args(["prepare", "0.28.0"])
        releaser.create_parser().parse_args(
            ["promote-rc", "1.0.0", "--remote", "origin"]
        )
        releaser.create_parser().parse_args(
            ["create-release-issue", "--version", "1.2.3rc4"]
        )

    def test_invalid_version(self):
        with self.assertRaises(SystemExit):
            releaser.create_parser().parse_args(["prepare", "0.28"])
        with self.assertRaises(SystemExit):
            releaser.create_parser().parse_args(["prepare", "a.b.c"])


if __name__ == "__main__":
    unittest.main()
