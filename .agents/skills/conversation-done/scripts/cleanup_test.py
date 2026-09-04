#!/usr/bin/env python3
"""Unit tests for the async cleanup script."""

import os
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

# Ensure scripts dir is in sys.path
sys_path = os.path.dirname(os.path.abspath(__file__))
if sys_path not in sys.path:
    sys.path.insert(0, sys_path)

import cleanup  # noqa: E402


class CleanupScriptTest(unittest.IsolatedAsyncioTestCase):
    """Tests for cleanup.py async logic and safety guards."""

    def test_is_protected_branch(self):
        """Verifies protected branches cannot be deleted."""
        self.assertTrue(cleanup.is_protected_branch("main"))
        self.assertTrue(cleanup.is_protected_branch("master"))
        self.assertTrue(cleanup.is_protected_branch("HEAD"))
        self.assertTrue(cleanup.is_protected_branch("release/1.0"))
        self.assertTrue(cleanup.is_protected_branch("release/2026-08"))
        self.assertTrue(cleanup.is_protected_branch("release-1.0"))
        self.assertTrue(cleanup.is_protected_branch("release-2026-08"))
        self.assertTrue(cleanup.is_protected_branch(None))
        self.assertFalse(cleanup.is_protected_branch("feature/my-cool-branch"))
        self.assertFalse(cleanup.is_protected_branch("bugfix-1234"))

    async def test_worktrees_parsing(self):
        """Verifies parsing git worktree list porcelain output."""
        sample_output = """worktree /path/to/main/repo
HEAD 03f212c3f3b590a7103d512650ce09818d30d218
branch refs/heads/main

worktree /path/to/worktrees/feat1
HEAD f130aea7fa0eab7d558897ed0ad915a1057e065c
branch refs/heads/feat1

worktree /path/to/worktrees/detached
HEAD 21e9bd5b3b069d4057abac69adf985b7907308f8
detached
"""
        with mock.patch("cleanup.run_command") as mock_run:
            mock_run.return_value = subprocess.CompletedProcess(
                args=[], returncode=0, stdout=sample_output, stderr=""
            )
            worktrees = await cleanup.get_worktrees("/path/to/main/repo")

        self.assertEqual(len(worktrees), 3)
        self.assertEqual(worktrees[0].path, "/path/to/main/repo")
        self.assertTrue(worktrees[0].is_main)
        self.assertEqual(worktrees[0].branch, "main")

        self.assertEqual(worktrees[1].path, "/path/to/worktrees/feat1")
        self.assertFalse(worktrees[1].is_main)
        self.assertEqual(worktrees[1].branch, "feat1")

        self.assertEqual(worktrees[2].path, "/path/to/worktrees/detached")
        self.assertFalse(worktrees[2].is_main)
        self.assertIsNone(worktrees[2].branch)

    def test_find_bazel_output_bases(self):
        """Verifies finding Bazel output bases matching target workspace."""
        with tempfile.TemporaryDirectory() as temp_dir:
            user_dir = os.path.join(temp_dir, "_bazel_testuser")
            os.makedirs(user_dir)

            # Output base 1: matches main worktree
            ob1 = os.path.join(user_dir, "hash1")
            os.makedirs(ob1)
            with open(os.path.join(ob1, "DO_NOT_BUILD_HERE"), "w") as f:
                f.write("/home/user/worktrees/my_feature\n")

            # Output base 2: matches nested integration workspace
            ob2 = os.path.join(user_dir, "hash2")
            os.makedirs(ob2)
            with open(os.path.join(ob2, "DO_NOT_BUILD_HERE"), "w") as f:
                f.write("/home/user/worktrees/my_feature/tests/integration/nested\n")

            # Output base 3: unrelated workspace
            ob3 = os.path.join(user_dir, "hash3")
            os.makedirs(ob3)
            with open(os.path.join(ob3, "DO_NOT_BUILD_HERE"), "w") as f:
                f.write("/home/user/worktrees/different_feature\n")

            with mock.patch("os.path.expanduser", return_value=temp_dir):
                bases = cleanup.find_bazel_output_bases(
                    "/home/user/worktrees/my_feature"
                )

            self.assertEqual(sorted(bases), sorted([ob1, ob2]))

    async def test_main_repo_safety(self):
        """Verifies refusal to remove main repository worktree."""
        main_repo = "/repo/main"
        target = cleanup.CleanupTarget(
            worktree_path="/repo/main",
            branch="main",
            is_main_worktree=True,
        )
        with mock.patch("cleanup.remove_git_worktree") as mock_rm_wt, mock.patch(
            "cleanup.log_error"
        ) as mock_log_err:
            await cleanup.execute_cleanup_target(main_repo, target)
            mock_rm_wt.assert_not_called()
            mock_log_err.assert_called_with(
                "Target is the main repository! Refusing to clean up main repository."
            )

    async def test_protected_branch_safety(self):
        """Verifies refusal to delete protected branch."""
        success, msg = await cleanup.delete_local_branch("/repo/main", "main")
        self.assertFalse(success)
        self.assertIn("protected", msg)

        success, msg = await cleanup.delete_remote_branch(
            "/repo/main", "main", "origin"
        )
        self.assertFalse(success)
        self.assertIn("protected", msg)

    async def test_upstream_remote_safety(self):
        """Verifies refusal to delete branch on upstream remote."""
        success, msg = await cleanup.delete_remote_branch(
            "/repo/main", "feature-x", "upstream"
        )
        self.assertFalse(success)
        self.assertIn("protected", msg)

    async def test_build_cleanup_target_branches(self):
        """Verifies building cleanup target for a branch."""
        with mock.patch(
            "cleanup.get_push_remote_for_branch", return_value="origin"
        ), mock.patch("cleanup.remote_branch_exists", return_value=True):
            target = await cleanup.build_cleanup_target(
                "/repo/main",
                "/repo/worktrees/feat1",
                "feat1",
            )
            self.assertEqual(target.worktree_path, "/repo/worktrees/feat1")
            self.assertEqual(target.branch, "feat1")
            self.assertEqual(target.remote, "origin")
            self.assertTrue(target.remote_branch_exists)


if __name__ == "__main__":
    unittest.main()
