import unittest
from unittest.mock import patch

from tools.private.release.gh import GitHub


class GitHubTest(unittest.TestCase):
    def setUp(self):
        self.gh = GitHub("my-owner/my-repo")

    @patch("tools.private.release.gh.run_cmd")
    def test_resolve_pr_number_digit(self, mock_run_cmd):
        # 124 and #125 should resolve immediately without running command
        self.assertEqual(self.gh.resolve_pr_number("124"), 124)
        self.assertEqual(self.gh.resolve_pr_number("#125"), 125)
        mock_run_cmd.assert_not_called()

    @patch("tools.private.release.gh.run_cmd")
    def test_resolve_pr_number_url_simple(self, mock_run_cmd):
        url = "https://github.com/my-owner/my-repo/pull/126"
        # Should resolve via regex without calling gh
        result = self.gh.resolve_pr_number(url)
        self.assertEqual(result, 126)
        mock_run_cmd.assert_not_called()

    @patch("tools.private.release.gh.run_cmd")
    def test_resolve_pr_number_url_with_subpath(self, mock_run_cmd):
        url = "https://github.com/my-owner/my-repo/pull/126/files"
        # Should resolve via regex without calling gh
        result = self.gh.resolve_pr_number(url)
        self.assertEqual(result, 126)
        mock_run_cmd.assert_not_called()

    @patch("tools.private.release.gh.run_cmd")
    def test_resolve_pr_number_url_with_query(self, mock_run_cmd):
        url = "https://github.com/my-owner/my-repo/pull/126/files?w=1"
        # Should resolve via regex without calling gh
        result = self.gh.resolve_pr_number(url)
        self.assertEqual(result, 126)
        mock_run_cmd.assert_not_called()

    @patch("tools.private.release.gh.run_cmd")
    def test_resolve_pr_number_url_other_repo(self, mock_run_cmd):
        # URL for a different repo should fail immediately without calling gh
        url = "https://github.com/other-owner/other-repo/pull/126"
        with self.assertRaises(ValueError) as ctx:
            self.gh.resolve_pr_number(url)
        self.assertIn("URL is not for the configured repository", str(ctx.exception))
        mock_run_cmd.assert_not_called()

    @patch("tools.private.release.gh.run_cmd")
    def test_resolve_pr_number_invalid_ref(self, mock_run_cmd):
        # Invalid reference (not number, not URL) should fail
        with self.assertRaises(ValueError) as ctx:
            self.gh.resolve_pr_number("invalid-ref")
        self.assertIn("Could not resolve PR reference", str(ctx.exception))
        mock_run_cmd.assert_not_called()


if __name__ == "__main__":
    unittest.main()
