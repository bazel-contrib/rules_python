"""Unit tests for the conversation-done workspace cleanup script."""

from __future__ import annotations

import asyncio
import os
import stat
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest import mock

import cleanup


class CleanupScriptTest(unittest.IsolatedAsyncioTestCase):
    """Tests for cleanup.py workspace resource discovery, ordering, and safety."""

    def test_is_protected_branch(self) -> None:
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

    async def test_worktrees_parsing(self) -> None:
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

    async def test_worktrees_failure_raises(self) -> None:
        """Verifies get_worktrees raises CleanupError when git worktree list fails."""
        with mock.patch("cleanup.run_command") as mock_run:
            mock_run.return_value = subprocess.CompletedProcess(
                args=[], returncode=128, stdout="", stderr="fatal: not a git repository"
            )
            with self.assertRaisesRegex(
                cleanup.CleanupError, "Failed to list Git worktrees"
            ):
                await cleanup.get_worktrees("/bad/repo")

    def test_find_bazel_output_bases(self) -> None:
        """Verifies finding Bazel output bases matching target workspace."""
        with tempfile.TemporaryDirectory() as temp_dir:
            user_dir = os.path.join(temp_dir, "_bazel_testuser")
            os.makedirs(user_dir)

            ob1 = os.path.join(user_dir, "hash1")
            os.makedirs(ob1)
            with open(
                os.path.join(ob1, "DO_NOT_BUILD_HERE"), "w", encoding="utf-8"
            ) as f:
                f.write("/home/user/worktrees/my_feature\n")

            ob2 = os.path.join(user_dir, "hash2")
            os.makedirs(ob2)
            with open(
                os.path.join(ob2, "DO_NOT_BUILD_HERE"), "w", encoding="utf-8"
            ) as f:
                f.write("/home/user/worktrees/my_feature/tests/integration/nested\n")

            ob3 = os.path.join(user_dir, "hash3")
            os.makedirs(ob3)
            with open(
                os.path.join(ob3, "DO_NOT_BUILD_HERE"), "w", encoding="utf-8"
            ) as f:
                f.write("/home/user/worktrees/different_feature\n")

            with mock.patch("os.path.expanduser", return_value=temp_dir):
                bases = cleanup.find_bazel_output_bases(
                    "/home/user/worktrees/my_feature"
                )

            self.assertEqual(sorted(bases), sorted([ob1, ob2]))

    async def test_main_repo_safety(self) -> None:
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
            deleted, succeeded = await cleanup.execute_cleanup_target(main_repo, target)
            self.assertEqual(deleted, [])
            self.assertFalse(succeeded)
            mock_rm_wt.assert_not_called()
            mock_log_err.assert_called_with(
                "Target is the main repository! Refusing to clean up main repository."
            )

    async def test_protected_branch_safety(self) -> None:
        """Verifies refusal to delete protected branch."""
        success, msg = await cleanup.delete_local_branch("/repo/main", "main")
        self.assertFalse(success)
        self.assertIn("protected", msg)

        success, msg = await cleanup.delete_remote_branch(
            "/repo/main", "main", "origin"
        )
        self.assertFalse(success)
        self.assertIn("protected", msg)

    async def test_missing_local_branch_succeeds(self) -> None:
        """Verifies delete_local_branch treats an already-deleted ref as success."""
        with mock.patch("cleanup.run_command") as mock_run, mock.patch(
            "cleanup.get_worktrees"
        ) as mock_get_wt:
            mock_run.return_value = subprocess.CompletedProcess(
                args=[], returncode=1, stdout="", stderr=""
            )
            ok, msg = await cleanup.delete_local_branch("/repo/main", "feat1")

        self.assertTrue(ok)
        self.assertEqual(msg, "Local branch 'feat1' does not exist.")
        mock_get_wt.assert_not_called()
        mock_run.assert_called_once_with(
            [
                "git",
                "-C",
                "/repo/main",
                "show-ref",
                "--verify",
                "--quiet",
                "refs/heads/feat1",
            ]
        )

    async def test_delete_local_branch_refusal_guards(self) -> None:
        """Verifies delete_local_branch refuses active worktrees and detach failures."""
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            main_repo = root / "main"
            target_wt = root / "wt_target"
            other_wt = root / "wt_other"
            main_repo.mkdir()
            target_wt.mkdir()
            other_wt.mkdir()
            worktrees = [
                cleanup.WorktreeInfo(str(main_repo), "abc", "feat_main", True),
                cleanup.WorktreeInfo(str(target_wt), "def", "feat_target", False),
                cleanup.WorktreeInfo(str(other_wt), "ghi", "feat_other", False),
            ]

            show_ref_ok = subprocess.CompletedProcess(
                args=[], returncode=0, stdout="", stderr=""
            )
            detach_fail = subprocess.CompletedProcess(
                args=[], returncode=128, stdout="", stderr="cannot lock ref 'HEAD'"
            )

            with mock.patch(
                "cleanup.get_worktrees", return_value=worktrees
            ), mock.patch("cleanup.run_command", return_value=show_ref_ok) as mock_run:
                ok, msg = await cleanup.delete_local_branch(
                    str(main_repo), "feat_other", worktree_path=str(target_wt)
                )
                self.assertFalse(ok)
                self.assertIn("still checked out in active worktree", msg)

                ok, msg = await cleanup.delete_local_branch(
                    str(main_repo), "feat_main", worktree_path=str(main_repo)
                )
                self.assertFalse(ok)
                self.assertIn("still checked out in active worktree", msg)
                for call in mock_run.call_args_list:
                    self.assertNotIn("branch", call.args[0])

            with mock.patch(
                "cleanup.get_worktrees", return_value=worktrees
            ), mock.patch(
                "cleanup.run_command", side_effect=[show_ref_ok, detach_fail]
            ) as mock_run:
                ok, msg = await cleanup.delete_local_branch(
                    str(main_repo), "feat_target", worktree_path=str(target_wt)
                )
                self.assertFalse(ok)
                self.assertIn("Failed to detach HEAD", msg)
                self.assertEqual(mock_run.call_count, 2)

    async def test_upstream_remote_safety(self) -> None:
        """Verifies refusal to delete branch on upstream remote."""
        success, msg = await cleanup.delete_remote_branch(
            "/repo/main", "feature-x", "upstream"
        )
        self.assertFalse(success)
        self.assertIn("protected", msg)

    async def test_build_cleanup_target_branches(self) -> None:
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

    async def test_execute_cleanup_target_reports_deleted_resources(self) -> None:
        """Verifies execute_cleanup_target deletes worktree last and reports order."""
        target = cleanup.CleanupTarget(
            worktree_path="/repo/worktrees/feat1",
            branch="feat1",
            remote="origin",
            remote_branch_exists=True,
            bazel_output_bases=["/cache/bazel/ob1"],
            is_main_worktree=False,
        )
        call_order: list[str] = []

        async def fake_rm_ob(*_args: object, **_kwargs: object) -> bool:
            call_order.append("bazel_output_base")
            return True

        async def fake_del_remote(
            *_args: object, **_kwargs: object
        ) -> tuple[bool, str]:
            call_order.append("remote_branch")
            return True, "Deleted remote branch 'feat1' from 'origin'."

        async def fake_del_local(*_args: object, **_kwargs: object) -> tuple[bool, str]:
            call_order.append("local_branch")
            return True, "Deleted local branch 'feat1'."

        async def fake_rm_wt(*_args: object, **_kwargs: object) -> bool:
            call_order.append("git_worktree")
            return True

        with mock.patch(
            "cleanup.get_path_size_human", return_value="1.50 GB"
        ), mock.patch(
            "cleanup.shutdown_and_remove_bazel_output_base",
            side_effect=fake_rm_ob,
        ), mock.patch(
            "cleanup.delete_remote_branch",
            side_effect=fake_del_remote,
        ), mock.patch(
            "cleanup.delete_local_branch",
            side_effect=fake_del_local,
        ) as mock_del_local, mock.patch(
            "cleanup.remove_git_worktree",
            side_effect=fake_rm_wt,
        ):
            deleted, succeeded = await cleanup.execute_cleanup_target(
                "/repo/main", target
            )

        self.assertTrue(succeeded)
        self.assertEqual(
            call_order,
            [
                "bazel_output_base",
                "remote_branch",
                "local_branch",
                "git_worktree",
            ],
        )
        mock_del_local.assert_called_once_with(
            "/repo/main",
            "feat1",
            worktree_path="/repo/worktrees/feat1",
            dry_run=False,
        )
        self.assertEqual(
            deleted,
            [
                "Bazel output base: /cache/bazel/ob1 (1.50 GB)",
                "Remote branch: origin/feat1",
                "Local branch: feat1",
                "Git worktree: /repo/worktrees/feat1",
            ],
        )

    async def test_skips_worktree_removal_on_earlier_failure(self) -> None:
        """Verifies worktree is not removed when any earlier cleanup step fails."""
        target = cleanup.CleanupTarget(
            worktree_path="/repo/worktrees/feat1",
            branch="feat1",
            remote="origin",
            remote_branch_exists=True,
            bazel_output_bases=["/cache/bazel/ob1"],
            is_main_worktree=False,
        )
        cases = [
            (
                "bazel_output_base",
                False,
                (True, "Deleted remote branch 'feat1' from 'origin'."),
                (True, "Deleted local branch 'feat1'."),
                True,
            ),
            (
                "remote_branch",
                True,
                (False, "Failed to delete remote branch."),
                (True, "Deleted local branch 'feat1'."),
                False,
            ),
            (
                "local_branch",
                True,
                (True, "Deleted remote branch 'feat1' from 'origin'."),
                (False, "Failed to delete local branch."),
                True,
            ),
        ]
        for name, ob_ok, remote_res, local_res, expect_local_called in cases:
            with self.subTest(failed_step=name), mock.patch(
                "cleanup.get_path_size_human", return_value="1.50 GB"
            ), mock.patch(
                "cleanup.shutdown_and_remove_bazel_output_base",
                return_value=ob_ok,
            ), mock.patch(
                "cleanup.delete_remote_branch",
                return_value=remote_res,
            ), mock.patch(
                "cleanup.delete_local_branch",
                return_value=local_res,
            ) as mock_del_local, mock.patch(
                "cleanup.remove_git_worktree"
            ) as mock_rm_wt:
                deleted, succeeded = await cleanup.execute_cleanup_target(
                    "/repo/main", target
                )
                self.assertFalse(succeeded)
                self.assertEqual(mock_del_local.called, expect_local_called)
                mock_rm_wt.assert_not_called()
                self.assertNotIn("Git worktree: /repo/worktrees/feat1", deleted)

    async def test_exits_nonzero_when_cleanup_fails(self) -> None:
        """Verifies async_main exits with code 1 and skips renaming on failure."""
        target = cleanup.CleanupTarget(
            worktree_path="/repo/worktrees/feat1",
            branch="feat1",
        )
        with mock.patch("cleanup.get_main_repo", return_value="/repo/main"), mock.patch(
            "cleanup.get_worktrees", return_value=[]
        ), mock.patch("cleanup.build_cleanup_target", return_value=target), mock.patch(
            "cleanup.execute_cleanup_target", return_value=([], False)
        ), mock.patch("cleanup.prefix_conversation_title") as mock_rename:
            with self.assertRaises(SystemExit) as cm:
                await cleanup.async_main(["--branches", "feat1", "--force"])

        self.assertEqual(cm.exception.code, 1)
        mock_rename.assert_not_called()

    async def test_remove_readonly_output_base_entries(self) -> None:
        """Verifies read-only files/dirs are removed without mutating symlink targets."""
        for force_python_fallback in (False, True):
            with self.subTest(
                force_python_fallback=force_python_fallback
            ), tempfile.TemporaryDirectory() as temp_dir:
                root = Path(temp_dir)
                external_file = root / "external_ro.txt"
                external_file.write_text("keep me\n", encoding="utf-8")
                external_file.chmod(0o444)

                external_dir = root / "external_ro_dir"
                external_dir.mkdir()
                external_dir.chmod(0o555)

                ob = root / "output_base"
                try:
                    ro_sandbox = ob / "sandbox" / "linux-sandbox" / "1"
                    ro_sandbox.mkdir(parents=True)
                    ro_file = ro_sandbox / "readonly.txt"
                    ro_file.write_text("artifact\n", encoding="utf-8")
                    ro_file.chmod(0o444)
                    (ro_sandbox / "file_link").symlink_to(external_file)
                    (ro_sandbox / "dir_link").symlink_to(external_dir)
                    ro_sandbox.chmod(0o555)
                    (ob / "sandbox").chmod(0o555)

                    no_exec_dir = ob / "no_exec"
                    no_exec_dir.mkdir()
                    (no_exec_dir / "inside.txt").write_text("x\n", encoding="utf-8")
                    no_exec_dir.chmod(0o600)

                    no_perm_dir = ob / "no_perm"
                    no_perm_dir.mkdir()
                    no_perm_file = no_perm_dir / "locked.txt"
                    no_perm_file.write_text("y\n", encoding="utf-8")
                    no_perm_file.chmod(0o000)
                    no_perm_dir.chmod(0o000)

                    if force_python_fallback:
                        rm_failed = subprocess.CompletedProcess(
                            args=["rm", "-rf", str(ob)],
                            returncode=1,
                            stdout="",
                            stderr="Permission denied",
                        )
                        with mock.patch("cleanup.run_command", return_value=rm_failed):
                            removed = await cleanup.remove_directory_safely(str(ob))
                    else:
                        removed = await cleanup.remove_directory_safely(str(ob))

                    self.assertTrue(removed)
                    self.assertFalse(ob.exists())
                    self.assertTrue(external_file.exists())
                    self.assertEqual(stat.S_IMODE(external_file.stat().st_mode), 0o444)
                    self.assertTrue(external_dir.exists())
                    self.assertEqual(stat.S_IMODE(external_dir.stat().st_mode), 0o555)
                finally:
                    cleanup._make_tree_writable(str(root))

    async def test_end_to_end_worktree_last_and_readonly_output_base(self) -> None:
        """Verifies real Git worktree/branch deletion and read-only output base cleanup."""
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            main_repo = root / "main"
            wt_dir = root / "wt_feat"
            bazel_cache = root / "bazel_cache"
            ob = bazel_cache / "_bazel_testuser" / "ob_hash"

            def setup_fixtures() -> None:
                remote_repo = root / "remote.git"
                subprocess.run(
                    ["git", "init", "--bare", str(remote_repo)],
                    check=True,
                    capture_output=True,
                )
                main_repo.mkdir()
                (main_repo / "README.md").write_text("init\n", encoding="utf-8")
                for cmd in (
                    ["git", "init", "-b", "main"],
                    ["git", "config", "user.email", "test@example.com"],
                    ["git", "config", "user.name", "Test"],
                    ["git", "remote", "add", "origin", str(remote_repo)],
                    ["git", "add", "README.md"],
                    ["git", "commit", "-m", "init"],
                    ["git", "worktree", "add", "-b", "feat", str(wt_dir), "main"],
                ):
                    subprocess.run(cmd, cwd=main_repo, check=True, capture_output=True)
                subprocess.run(
                    ["git", "push", "origin", "feat"],
                    cwd=wt_dir,
                    check=True,
                    capture_output=True,
                )
                (wt_dir / "dirty.txt").write_text("uncommitted\n", encoding="utf-8")

                ro_dir = ob / "external" / "ro_pkg"
                ro_dir.mkdir(parents=True)
                (ob / "DO_NOT_BUILD_HERE").write_text(f"{wt_dir}\n", encoding="utf-8")
                ro_file = ro_dir / "pkg.bzl"
                ro_file.write_text("X = 1\n", encoding="utf-8")
                ro_file.chmod(0o444)
                ro_dir.chmod(0o555)

            try:
                await asyncio.to_thread(setup_fixtures)
                real_run_command = cleanup.run_command

                async def run_without_bazel_server(
                    cmd: list[str],
                    cwd: str | None = None,
                    capture_output: bool = True,
                    timeout: float | None = None,
                ) -> subprocess.CompletedProcess[str]:
                    if cmd and cmd[0] == "bazel":
                        return subprocess.CompletedProcess(
                            args=cmd, returncode=0, stdout="", stderr=""
                        )
                    return await real_run_command(
                        cmd,
                        cwd=cwd,
                        capture_output=capture_output,
                        timeout=timeout,
                    )

                with mock.patch(
                    "os.path.expanduser", return_value=str(bazel_cache)
                ), mock.patch(
                    "cleanup.run_command", side_effect=run_without_bazel_server
                ), mock.patch("cleanup.terminate_processes_under_path"):
                    target = await cleanup.build_cleanup_target(
                        str(main_repo), str(wt_dir), "feat"
                    )
                    deleted, succeeded = await cleanup.execute_cleanup_target(
                        str(main_repo), target
                    )

                self.assertTrue(succeeded)
                self.assertFalse(ob.exists())
                self.assertFalse(wt_dir.exists())
                self.assertEqual(len(deleted), 4)
                self.assertTrue(deleted[0].startswith("Bazel output base:"))
                self.assertEqual(deleted[1], "Remote branch: origin/feat")
                self.assertEqual(deleted[2], "Local branch: feat")
                self.assertEqual(deleted[3], f"Git worktree: {wt_dir}")

                branches = await real_run_command(
                    ["git", "-C", str(main_repo), "branch", "--list", "feat"]
                )
                self.assertEqual(branches.stdout.strip(), "")
                remote_branches = await real_run_command(
                    [
                        "git",
                        "-C",
                        str(main_repo),
                        "ls-remote",
                        "--heads",
                        "origin",
                        "feat",
                    ]
                )
                self.assertEqual(remote_branches.stdout.strip(), "")
            finally:
                cleanup._make_tree_writable(str(root))

    def test_format_done_title(self) -> None:
        """Verifies prepending 'done ' without duplication and 70-char truncation."""
        self.assertEqual(
            cleanup.format_done_title("Fix flaky upload test"),
            "done Fix flaky upload test",
        )
        self.assertEqual(
            cleanup.format_done_title("done Fix flaky upload test"),
            "done Fix flaky upload test",
        )
        self.assertEqual(
            cleanup.format_done_title("DONE   Fix flaky upload test"),
            "done Fix flaky upload test",
        )
        self.assertEqual(cleanup.format_done_title("   "), "done")
        long_title = "a" * 80
        formatted = cleanup.format_done_title(long_title)
        self.assertEqual(len(formatted), 70)
        self.assertTrue(formatted.startswith("done "))


if __name__ == "__main__":
    unittest.main()
