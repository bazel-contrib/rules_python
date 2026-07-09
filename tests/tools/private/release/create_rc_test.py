import argparse
import os
import pathlib
import tempfile
import unittest
from unittest.mock import MagicMock, call, patch

from tests.tools.private.release.release_test_helper import _mock_git_and_gh
from tools.private.release.create_rc import CreateRc


class CmdCreateRcTest(unittest.TestCase):
    def setUp(self):
        _mock_git_and_gh(self)

    def test_create_rc_success_first_rc(self):
        # Arrange
        args = MagicMock(issue=123, remote="my-remote")
        self.mock_gh.get_issue_title.return_value = "Release 2.0.0"
        self.mock_gh.get_issue_body.return_value = """
## Checklist
- [x] Prepare Release | status=done pr=#122 commit=abcdef12
- [x] Create Release branch | status=done branch=release/2.0 commit=abcdef12
- [ ] Tag RC0 | status=pending
"""
        self.mock_git.get_remote_tags.return_value = []
        self.mock_git.get_commit_sha.return_value = "1234567890"

        # Act
        with tempfile.TemporaryDirectory() as tmpdir:
            github_output_file = pathlib.Path(tmpdir) / "github_output"
            with patch.dict(os.environ, {"GITHUB_OUTPUT": str(github_output_file)}):
                result = CreateRc(args, self.mock_git, self.mock_gh).run()

            # Assert
            self.assertEqual(result, 0)
            self.assertTrue(github_output_file.exists())
            self.assertEqual(github_output_file.read_text(), "tag_name=2.0.0-rc0\n")
        self.mock_git.fetch.assert_has_calls(
            [call("my-remote"), call("my-remote", tags=True, force=True)]
        )
        self.mock_git.checkout.assert_not_called()
        self.mock_git.tag.assert_called_once_with("2.0.0-rc0", "my-remote/release/2.0")
        self.mock_git.push.assert_called_once_with("my-remote", "2.0.0-rc0")
        self.mock_git.get_commit_sha.assert_called_once_with("my-remote/release/2.0")

        self.mock_gh.update_issue_body.assert_called_once()
        call_args = self.mock_gh.update_issue_body.call_args[0]
        self.assertEqual(call_args[0], 123)
        self.assertIn("tag=2.0.0-rc0", call_args[1])
        self.assertIn("commit= 12345678", call_args[1])

        self.mock_gh.post_issue_comment.assert_called_once()
        comment_call_args = self.mock_gh.post_issue_comment.call_args[0]
        self.assertEqual(comment_call_args[0], 123)
        self.assertIn(
            "**New Release Candidate Tagged!** 🐍🌿",
            comment_call_args[1],
        )
        self.assertIn(
            "tagged on branch [`release/2.0`](https://github.com/bazel-contrib/rules_python/tree/release/2.0)",
            comment_call_args[1],
        )
        self.assertIn(
            "- [Github Release 2.0.0-rc0](https://github.com/bazel-contrib/rules_python/releases/tag/2.0.0-rc0)",
            comment_call_args[1],
        )
        self.assertIn(
            "- [BCR Entry 2.0.0-rc0](https://registry.bazel.build/modules/rules_python/2.0.0-rc0)",
            comment_call_args[1],
        )
        self.assertIn(
            "- [BCR PRs](https://github.com/bazelbuild/bazel-central-registry/pulls?q=is%3Apr+rules_python+2.0.0-rc0)",
            comment_call_args[1],
        )
        self.assertIn(
            "- [Release workflow status](https://github.com/bazel-contrib/rules_python/actions/workflows/release_create_rc.yaml)",
            comment_call_args[1],
        )

    def test_create_rc_success_with_run_id(self):
        # Arrange
        args = MagicMock(issue=123, remote="my-remote")
        self.mock_gh.get_issue_title.return_value = "Release 2.0.0"
        self.mock_gh.get_issue_body.return_value = """
## Checklist
- [x] Prepare Release | status=done pr=#122 commit=abcdef12
- [x] Create Release branch | status=done branch=release/2.0 commit=abcdef12
- [ ] Tag RC0 | status=pending
"""
        self.mock_git.get_remote_tags.return_value = []
        self.mock_git.get_commit_sha.return_value = "1234567890"

        # Act
        with patch.dict(os.environ, {"GITHUB_RUN_ID": "987654321"}):
            result = CreateRc(args, self.mock_git, self.mock_gh).run()

        # Assert
        self.assertEqual(result, 0)
        self.mock_gh.post_issue_comment.assert_called_once()
        comment_call_args = self.mock_gh.post_issue_comment.call_args[0]
        self.assertIn(
            "- [Release workflow status](https://github.com/bazel-contrib/rules_python/actions/runs/987654321)",
            comment_call_args[1],
        )
        self.assertIn(
            "tagged on branch [`release/2.0`](https://github.com/bazel-contrib/rules_python/tree/release/2.0)",
            comment_call_args[1],
        )

    def test_create_rc_success_next_rc(self):
        # Arrange
        args = MagicMock(issue=123, remote="my-remote")
        self.mock_gh.get_issue_title.return_value = "Release 2.0.0"
        self.mock_gh.get_issue_body.return_value = """
## Checklist
- [x] Prepare Release | status=done pr=#122 commit=abcdef12
- [x] Create Release branch | status=done branch=release/2.0 commit=abcdef12
- [x] Tag RC0 | status=done tag=2.0.0-rc0 commit=abcdef12
- [ ] Tag RC1 | status=pending
"""
        self.mock_git.get_remote_tags.return_value = ["2.0.0-rc0"]
        self.mock_git.get_commit_sha.return_value = "1234567890"

        # Act
        result = CreateRc(args, self.mock_git, self.mock_gh).run()

        # Assert
        self.assertEqual(result, 0)
        self.mock_git.fetch.assert_has_calls(
            [call("my-remote"), call("my-remote", tags=True, force=True)]
        )
        self.mock_git.checkout.assert_not_called()
        self.mock_git.tag.assert_called_once_with("2.0.0-rc1", "my-remote/release/2.0")
        self.mock_git.push.assert_called_once_with("my-remote", "2.0.0-rc1")
        self.mock_git.get_commit_sha.assert_called_once_with("my-remote/release/2.0")

        self.mock_gh.update_issue_body.assert_called_once()
        call_args = self.mock_gh.update_issue_body.call_args[0]
        self.assertEqual(call_args[0], 123)
        self.assertIn("tag=2.0.0-rc1", call_args[1])

        self.mock_gh.post_issue_comment.assert_called_once()
        comment_call_args = self.mock_gh.post_issue_comment.call_args[0]
        self.assertEqual(comment_call_args[0], 123)
        self.assertIn(
            "**New Release Candidate Tagged!** 🐍🌿",
            comment_call_args[1],
        )
        self.assertIn(
            "tagged on branch [`release/2.0`](https://github.com/bazel-contrib/rules_python/tree/release/2.0)",
            comment_call_args[1],
        )
        self.assertIn(
            "- [Github Release 2.0.0-rc1](https://github.com/bazel-contrib/rules_python/releases/tag/2.0.0-rc1)",
            comment_call_args[1],
        )
        self.assertIn(
            "- [BCR Entry 2.0.0-rc1](https://registry.bazel.build/modules/rules_python/2.0.0-rc1)",
            comment_call_args[1],
        )
        self.assertIn(
            "- [BCR PRs](https://github.com/bazelbuild/bazel-central-registry/pulls?q=is%3Apr+rules_python+2.0.0-rc1)",
            comment_call_args[1],
        )
        self.assertIn(
            "- [Release workflow status](https://github.com/bazel-contrib/rules_python/actions/workflows/release_create_rc.yaml)",
            comment_call_args[1],
        )

    def test_create_rc_gating_on_backports(self):
        # Arrange
        args = MagicMock(issue=123, remote="my-remote")
        self.mock_gh.get_issue_title.return_value = "Release 2.0.0"
        self.mock_gh.get_issue_body.return_value = """
## Checklist
- [x] Prepare Release | status=done pr=#122 commit=abcdef12
- [x] Create Release branch | status=done branch=release/2.0 commit=abcdef12
- [ ] Tag RC0 | status=pending

## Backports
- [ ] #124 | status=pending
"""
        # Act
        result = CreateRc(args, self.mock_git, self.mock_gh).run()

        # Assert
        self.assertEqual(result, 1)
        self.mock_git.tag.assert_not_called()
        self.mock_git.push.assert_not_called()

    def test_create_rc_not_blocked_by_ignored_backports(self):
        # Arrange
        args = MagicMock(issue=123, remote="my-remote")
        self.mock_gh.get_issue_title.return_value = "Release 2.0.0"
        self.mock_gh.get_issue_body.return_value = """
## Checklist
- [x] Prepare Release | status=done pr=#122 commit=abcdef12
- [x] Create Release branch | status=done branch=release/2.0 commit=abcdef12
- [ ] Tag RC0 | status=pending

## Backports
- [ ] #124 | status=ignore
"""
        self.mock_git.get_remote_tags.return_value = []
        self.mock_git.get_commit_sha.return_value = "1234567890"

        # Act
        result = CreateRc(args, self.mock_git, self.mock_gh).run()

        # Assert
        self.assertEqual(result, 0)
        self.mock_git.tag.assert_called_once_with("2.0.0-rc0", "my-remote/release/2.0")
        self.mock_git.push.assert_called_once_with("my-remote", "2.0.0-rc0")

    def test_create_rc_with_finished_backports(self):
        # Arrange
        args = MagicMock(issue=123, remote="my-remote")
        self.mock_gh.get_issue_title.return_value = "Release 2.0.0"
        self.mock_gh.get_issue_body.return_value = """
## Checklist
- [x] Prepare Release | status=done pr=#122 commit=abcdef12
- [x] Create Release branch | status=done branch=release/2.0 commit=abcdef12
- [ ] Tag RC0 | status=pending

## Backports
- [x] #124 | status=done rc=rc0 commit=abcdef12
"""
        self.mock_git.get_remote_tags.return_value = []
        self.mock_git.get_commit_sha.return_value = "1234567890"

        # Act
        result = CreateRc(args, self.mock_git, self.mock_gh).run()

        # Assert
        self.assertEqual(result, 0)
        self.mock_git.tag.assert_called_once_with("2.0.0-rc0", "my-remote/release/2.0")
        self.mock_git.push.assert_called_once_with("my-remote", "2.0.0-rc0")

    def test_create_rc_auto_add_task(self):
        # Arrange
        args = argparse.Namespace(issue=123, remote="my-remote")
        self.mock_gh.get_issue_title.return_value = "Release 2.0.0"
        self.mock_gh.get_issue_body.return_value = """
## Checklist
- [x] Prepare Release | status=done pr=#122 commit=abcdef12
- [x] Create Release branch | status=done branch=release/2.0 commit=abcdef12
- [x] Tag RC0 | status=done tag=2.0.0-rc0 commit=abcdef12
- [ ] Tag Final
"""
        self.mock_git.get_remote_tags.return_value = ["2.0.0-rc0"]
        self.mock_git.get_commit_sha.return_value = "1234567890"

        # Act
        result = CreateRc(args, self.mock_git, self.mock_gh).run()

        # Assert
        self.assertEqual(result, 0)
        self.mock_git.tag.assert_called_once_with("2.0.0-rc1", "my-remote/release/2.0")
        self.mock_git.push.assert_called_once_with("my-remote", "2.0.0-rc1")

        self.assertEqual(self.mock_gh.update_issue_body.call_count, 2)
        call1_args = self.mock_gh.update_issue_body.call_args_list[0][0]
        call2_args = self.mock_gh.update_issue_body.call_args_list[1][0]

        self.assertEqual(call1_args[0], 123)
        self.assertIn("- [ ] Tag RC1", call1_args[1])
        self.assertIn(
            "- [x] Tag RC0 | status=done tag=2.0.0-rc0 commit=abcdef12\n- [ ]"
            " Tag RC1\n- [ ] Tag Final",
            call1_args[1].strip(),
        )

        self.assertEqual(call2_args[0], 123)
        self.assertIn(
            "- [x] Tag RC1 | status=done tag=2.0.0-rc1 commit= 12345678",
            call2_args[1],
        )

    @patch("tools.private.release.create_rc.ProcessBackports")
    def test_create_rc_calls_process_backports(self, mock_pb_class):
        # Arrange
        mock_pb = mock_pb_class.return_value
        mock_pb.run.return_value = 0

        args = MagicMock(issue=123, remote="my-remote")
        self.mock_gh.get_issue_title.return_value = "Release 2.0.0"
        self.mock_gh.get_issue_body.return_value = """
## Checklist
- [x] Prepare Release | status=done pr=#122 commit=abcdef12
- [x] Create Release branch | status=done branch=release/2.0 commit=abcdef12
- [ ] Tag RC0 | status=pending
"""
        self.mock_git.get_remote_tags.return_value = []
        self.mock_git.get_commit_sha.return_value = "1234567890"

        # Act
        result = CreateRc(args, self.mock_git, self.mock_gh).run()

        # Assert
        self.assertEqual(result, 0)
        mock_pb_class.assert_called_once()
        called_args = mock_pb_class.call_args[0][0]
        self.assertEqual(called_args.issue, 123)
        self.assertEqual(called_args.remote, "my-remote")
        self.assertFalse(called_args.dry_run)
        self.assertIsNone(called_args.add)
        self.assertIsNone(called_args.triggering_comment)
        mock_pb.run.assert_called_once()

    @patch("tools.private.release.create_rc.ProcessBackports")
    def test_create_rc_aborts_on_process_backports_failure(self, mock_pb_class):
        # Arrange
        mock_pb = mock_pb_class.return_value
        mock_pb.run.return_value = 1

        args = MagicMock(issue=123, remote="my-remote")

        # Act
        result = CreateRc(args, self.mock_git, self.mock_gh).run()

        # Assert
        self.assertEqual(result, 1)
        mock_pb_class.assert_called_once()
        mock_pb.run.assert_called_once()
        self.mock_gh.get_issue_body.assert_not_called()
        self.mock_git.tag.assert_not_called()

    @patch("tools.private.release.create_rc.ProcessBackports")
    def test_create_rc_failure_reacts_to_comment(self, mock_pb_class):
        # Arrange
        mock_pb = mock_pb_class.return_value
        mock_pb.run.return_value = 1  # Simulate failure

        args = MagicMock(issue=123, remote="my-remote", triggering_comment=456)

        # Act
        result = CreateRc(args, self.mock_git, self.mock_gh).run()

        # Assert
        self.assertEqual(result, 1)
        self.mock_gh.add_comment_reaction.assert_called_once_with(456, "-1")

    @patch("tools.private.release.create_rc.ProcessBackports")
    def test_create_rc_failure_no_comment_no_reaction(self, mock_pb_class):
        # Arrange
        mock_pb = mock_pb_class.return_value
        mock_pb.run.return_value = 1  # Simulate failure

        args = MagicMock(issue=123, remote="my-remote", triggering_comment=None)

        # Act
        result = CreateRc(args, self.mock_git, self.mock_gh).run()

        # Assert
        self.assertEqual(result, 1)
        self.mock_gh.add_comment_reaction.assert_not_called()

    @patch("tools.private.release.create_rc.ProcessBackports")
    def test_create_rc_success_with_comment_no_reaction(self, mock_pb_class):
        # Arrange
        mock_pb = mock_pb_class.return_value
        mock_pb.run.return_value = 0

        args = MagicMock(issue=123, remote="my-remote", triggering_comment=456)
        self.mock_gh.get_issue_title.return_value = "Release 2.0.0"
        self.mock_gh.get_issue_body.return_value = """
## Checklist
- [x] Prepare Release | status=done pr=#122 commit=abcdef12
- [x] Create Release branch | status=done branch=release/2.0 commit=abcdef12
- [ ] Tag RC0 | status=pending
"""
        self.mock_git.get_remote_tags.return_value = []
        self.mock_git.get_commit_sha.return_value = "1234567890"

        # Act
        result = CreateRc(args, self.mock_git, self.mock_gh).run()

        # Assert
        self.assertEqual(result, 0)
        self.mock_gh.add_comment_reaction.assert_not_called()

    @patch("tools.private.release.create_rc.ProcessBackports")
    def test_create_rc_precondition_failure_reacts_to_comment(self, mock_pb_class):
        # Arrange
        mock_pb = mock_pb_class.return_value
        mock_pb.run.return_value = 0  # Backports succeed

        args = MagicMock(issue=123, remote="my-remote", triggering_comment=456)
        self.mock_gh.get_issue_body.return_value = """
## Checklist
- [ ] Prepare Release | status=pending
- [ ] Create Release branch | status=pending
- [ ] Tag RC0 | status=pending
"""

        # Act
        result = CreateRc(args, self.mock_git, self.mock_gh).run()

        # Assert
        self.assertEqual(result, 1)
        self.mock_gh.add_comment_reaction.assert_called_once_with(456, "-1")


if __name__ == "__main__":
    unittest.main()
