#!/usr/bin/env python3
"""Cleans up workspace resources created for an agent conversation.

This script cleans up files and resources that are external to the agent
conversation itself (such as Bazel output bases, Git worktrees, and local or
remote Git branches), while leaving the conversation history, transcripts,
and brain state intact.

Usage examples:
  # Clean up current worktree and its associated resources:
  cleanup.py

  # Preview what would be cleaned up without making changes:
  cleanup.py --dry-run

  # Clean up a specific worktree by path:
  cleanup.py --worktree /path/to/worktree

  # Clean up resources for specific branches:
  cleanup.py --branches my-feature-branch

  # Clean up resources for multiple branches:
  cleanup.py --branches branch-one branch-two

  # List worktrees and their associated resources:
  cleanup.py --list
"""

from __future__ import annotations

import argparse
import asyncio
import dataclasses
import glob
import json
import os
import shutil
import signal
import stat
import subprocess
import sys
import urllib.error
import urllib.request
from collections.abc import Sequence

_PROTECTED_BRANCHES = frozenset(
    {
        # keep-sorted start
        "HEAD",
        "main",
        "master",
        # keep-sorted end
    }
)
_PROTECTED_REMOTES = frozenset(
    {
        # keep-sorted start
        "upstream",
        # keep-sorted end
    }
)
# Maximum conversation title length displayed by the UI.
_CONVERSATION_TITLE_MAX_LENGTH = 70
_DONE_TITLE_PREFIX = "done "
# Bound urllib.request.urlopen (which has no default timeout) on local loopback RPCs.
_LS_RPC_TIMEOUT_SECONDS = 5
# Cap git ls-remote so unreachable remotes do not stall cleanup.
_GIT_LS_REMOTE_TIMEOUT_SECONDS = 10
# Bound du -sk so large output bases do not stall informational size reporting.
_DU_TIMEOUT_SECONDS = 5
# Bound graceful bazel shutdown before falling back to SIGTERM/SIGKILL.
_BAZEL_SHUTDOWN_TIMEOUT_SECONDS = 10
# Grace period for a lingering Bazel JVM server to exit on SIGTERM before SIGKILL.
_SIGTERM_GRACE_SECONDS = 0.5
# Allow network round-trips when deleting a remote branch via git push.
_GIT_PUSH_DELETE_TIMEOUT_SECONDS = 30
_GET_TRAJECTORIES_METHOD = (
    "exa.language_server_pb.LanguageServerService/GetAllCascadeTrajectories"
)
_UPDATE_ANNOTATIONS_METHOD = (
    "exa.language_server_pb.LanguageServerService/UpdateConversationAnnotations"
)


def parse_args(argv: Sequence[str]) -> argparse.Namespace:
    """Parses command-line arguments."""
    parser = argparse.ArgumentParser(
        description="Clean up agent workspace resources (Bazel output base, worktree, branches)."
    )
    parser.add_argument(
        "--worktree",
        type=str,
        default=None,
        help="Path to the Git worktree to clean up.",
    )
    parser.add_argument(
        "--branches",
        nargs="+",
        default=[],
        help="One or more branch names to clean up.",
    )
    parser.add_argument(
        "--remote",
        type=str,
        default=None,
        help="Remote name for remote branch deletion (default: pushRemote or origin).",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Preview resources to delete without making changes.",
    )
    # -f is the standard short alias for non-interactive confirmation when invoked by scripts.
    parser.add_argument(
        "-f",
        "--force",
        action="store_true",
        help="Proceed with cleanup without interactive confirmation.",
    )
    parser.add_argument(
        "--list",
        action="store_true",
        help="List worktrees, branches, and associated Bazel output bases.",
    )
    parser.add_argument(
        "--leave-bazel-output-base",
        action="store_true",
        help="Leave Bazel output bases and build caches intact.",
    )
    parser.add_argument(
        "--leave-worktree",
        action="store_true",
        help="Leave Git worktree directory on disk.",
    )
    parser.add_argument(
        "--leave-branch",
        action="store_true",
        help="Keep local Git branch.",
    )
    parser.add_argument(
        "--leave-remote",
        action="store_true",
        help="Do not delete branch from remote fork.",
    )
    return parser.parse_args(argv)


def log(msg: str) -> None:
    """Prints an informational message."""
    print(msg, flush=True)


def log_warn(msg: str) -> None:
    """Prints a warning message to stderr."""
    print(f"Warning: {msg}", file=sys.stderr, flush=True)


def log_error(msg: str) -> None:
    """Prints an error message to stderr."""
    print(f"Error: {msg}", file=sys.stderr, flush=True)


async def run_command(
    cmd: list[str],
    cwd: str | None = None,
    capture_output: bool = True,
    timeout: float | None = None,
) -> subprocess.CompletedProcess[str]:
    """Executes a subprocess command and returns its completed result."""
    stdout_pipe = asyncio.subprocess.PIPE if capture_output else None
    stderr_pipe = asyncio.subprocess.PIPE if capture_output else None
    try:
        proc = await asyncio.create_subprocess_exec(
            *cmd,
            cwd=cwd,
            stdout=stdout_pipe,
            stderr=stderr_pipe,
        )
        try:
            stdout_b, stderr_b = await asyncio.wait_for(
                proc.communicate(), timeout=timeout
            )
        except asyncio.TimeoutError:
            try:
                proc.kill()
                await proc.wait()
            except OSError:
                pass
            return subprocess.CompletedProcess(
                args=cmd,
                returncode=1,
                stdout="",
                stderr=f"Command timed out after {timeout} seconds",
            )
        stdout = stdout_b.decode("utf-8", errors="replace") if stdout_b else ""
        stderr = stderr_b.decode("utf-8", errors="replace") if stderr_b else ""
        return subprocess.CompletedProcess(
            args=cmd,
            returncode=proc.returncode if proc.returncode is not None else 0,
            stdout=stdout,
            stderr=stderr,
        )
    except (FileNotFoundError, OSError) as exc:
        return subprocess.CompletedProcess(
            args=cmd,
            returncode=1,
            stdout="",
            stderr=str(exc),
        )


async def get_main_repo(cwd: str | None = None) -> str:
    """Finds the root directory of the primary Git repository."""
    res = await run_command(["git", "rev-parse", "--git-common-dir"], cwd=cwd)
    if res.returncode == 0 and res.stdout.strip():
        git_common = os.path.abspath(res.stdout.strip())
        if os.path.basename(git_common) == ".git":
            return os.path.dirname(git_common)
        return git_common

    res = await run_command(["git", "rev-parse", "--show-toplevel"], cwd=cwd)
    if res.returncode == 0 and res.stdout.strip():
        return os.path.abspath(res.stdout.strip())

    raise CleanupError("Not inside a Git repository.")


async def get_current_worktree(cwd: str | None = None) -> str | None:
    """Returns the top-level directory of the current worktree, if any."""
    res = await run_command(["git", "rev-parse", "--show-toplevel"], cwd=cwd)
    if res.returncode == 0 and res.stdout.strip():
        return os.path.abspath(res.stdout.strip())
    return None


async def get_worktrees(main_repo: str) -> list[WorktreeInfo]:
    """Returns all Git worktrees registered in the repository."""
    res = await run_command(["git", "-C", main_repo, "worktree", "list", "--porcelain"])
    if res.returncode != 0:
        raise CleanupError(f"Failed to list Git worktrees: {res.stderr.strip()}")

    worktrees: list[WorktreeInfo] = []
    current_wt: str | None = None
    current_head = ""
    current_branch: str | None = None

    for line in res.stdout.splitlines():
        line = line.strip()
        if line.startswith("worktree "):
            if current_wt:
                worktrees.append(
                    WorktreeInfo(
                        path=current_wt,
                        head=current_head,
                        branch=current_branch,
                        is_main=len(worktrees) == 0,
                    )
                )
            current_wt = line.split("worktree ", 1)[1].strip()
            current_head = ""
            current_branch = None
        elif line.startswith("HEAD "):
            current_head = line.split("HEAD ", 1)[1].strip()
        elif line.startswith("branch refs/heads/"):
            current_branch = line.split("branch refs/heads/", 1)[1].strip()

    if current_wt:
        worktrees.append(
            WorktreeInfo(
                path=current_wt,
                head=current_head,
                branch=current_branch,
                is_main=len(worktrees) == 0,
            )
        )

    return worktrees


def is_protected_branch(branch: str | None) -> bool:
    """Checks if a branch is protected from deletion."""
    if not branch:
        return True
    if branch in _PROTECTED_BRANCHES:
        return True
    if branch.startswith("release/") or branch.startswith("release-"):
        return True
    return False


async def get_push_remote_for_branch(main_repo: str, branch: str) -> str:
    """Determines the push remote for a branch, defaulting to 'origin'."""
    res = await run_command(
        ["git", "-C", main_repo, "config", f"branch.{branch}.pushRemote"]
    )
    remote = res.stdout.strip()
    if remote:
        return remote

    res = await run_command(
        ["git", "-C", main_repo, "config", f"branch.{branch}.remote"]
    )
    remote = res.stdout.strip()
    if remote and remote not in _PROTECTED_REMOTES:
        return remote

    return "origin"


async def remote_branch_exists(main_repo: str, remote: str, branch: str) -> bool:
    """Checks whether a branch exists on the specified remote."""
    if remote in _PROTECTED_REMOTES or is_protected_branch(branch):
        return False
    res = await run_command(
        ["git", "-C", main_repo, "ls-remote", "--heads", remote, branch],
        timeout=_GIT_LS_REMOTE_TIMEOUT_SECONDS,
    )
    return res.returncode == 0 and bool(res.stdout.strip())


def find_bazel_output_bases(target_worktree: str) -> list[str]:
    """Finds all Bazel output bases associated with a worktree path."""
    target_worktree = os.path.realpath(target_worktree)
    output_bases: list[str] = []

    user_cache = os.path.expanduser("~/.cache/bazel")
    if not os.path.isdir(user_cache):
        return output_bases

    for user_dir in glob.glob(os.path.join(user_cache, "_bazel_*")):
        if not os.path.isdir(user_dir):
            continue
        for ob in glob.glob(os.path.join(user_dir, "*")):
            if not os.path.isdir(ob) or os.path.basename(ob) in ("cache", "install"):
                continue
            dnbh = os.path.join(ob, "DO_NOT_BUILD_HERE")
            if os.path.isfile(dnbh):
                try:
                    with open(dnbh, "r", encoding="utf-8") as f:
                        ws = os.path.realpath(f.read().strip())
                    if ws == target_worktree or ws.startswith(target_worktree + os.sep):
                        output_bases.append(ob)
                except OSError:
                    pass

    return sorted(list(set(output_bases)))


async def get_path_size_human(path: str) -> str:
    """Returns human-readable size of a directory path."""
    if not os.path.exists(path):
        return "0 B"
    res = await run_command(["du", "-sk", path], timeout=_DU_TIMEOUT_SECONDS)
    if res.returncode == 0 and res.stdout.strip():
        try:
            kb = int(res.stdout.split()[0])
            if kb < 1024:
                return f"{kb} KB"
            mb = kb / 1024.0
            if mb < 1024:
                return f"{mb:.1f} MB"
            gb = mb / 1024.0
            return f"{gb:.2f} GB"
        except (ValueError, IndexError):
            pass
    return "unknown size"


async def shutdown_and_remove_bazel_output_base(
    output_base: str, dry_run: bool = False
) -> bool:
    """Cleanly shuts down the Bazel server and removes the output base directory."""
    if dry_run:
        log(
            f"  [Dry Run] Would shutdown Bazel server and delete output base: {output_base}"
        )
        return True

    log(f"  Shutting down Bazel server for output base: {output_base}")
    # 1. Graceful shutdown command
    await run_command(
        ["bazel", f"--output_base={output_base}", "shutdown"],
        timeout=_BAZEL_SHUTDOWN_TIMEOUT_SECONDS,
    )

    # 2. Check for running server process from server.pid.txt
    server_pid_file = os.path.join(output_base, "server", "server.pid.txt")
    if os.path.isfile(server_pid_file):
        try:
            with open(server_pid_file, "r", encoding="utf-8") as f:
                pid = int(f.read().strip())
            os.kill(pid, 0)
            log(f"  Terminating lingering Bazel server process (PID: {pid})...")
            os.kill(pid, signal.SIGTERM)
            await asyncio.sleep(_SIGTERM_GRACE_SECONDS)
            try:
                os.kill(pid, signal.SIGKILL)
            except OSError:
                pass
        except (ValueError, OSError):
            pass

    # 3. Terminate any persistent workers or subprocesses tied to this output base
    terminate_processes_under_path(output_base)

    # 4. Remove output base directory (NEVER run bazel clean --expunge per rules)
    log(f"  Removing Bazel output base directory: {output_base}")
    return await remove_directory_safely(output_base)


def terminate_processes_under_path(path: str) -> None:
    """Terminates active processes running binaries or workers inside path."""
    current_pid = os.getpid()
    if not os.path.isdir("/proc"):
        return

    real_path = os.path.realpath(path)
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        pid = int(entry)
        if pid == current_pid or pid == 1:
            continue
        try:
            exe = os.path.realpath(f"/proc/{pid}/exe")
            if exe.startswith(real_path + os.sep):
                os.kill(pid, signal.SIGTERM)
                continue
            with open(f"/proc/{pid}/cmdline", "rb") as f:
                cmdline = f.read().decode("utf-8", errors="ignore")
            if real_path in cmdline:
                os.kill(pid, signal.SIGTERM)
        except (OSError, FileNotFoundError):
            continue


def _ensure_writable(entry_path: str) -> None:
    """Grants owner access on regular files and directories without following symlinks.

    Args:
        entry_path: Filesystem path whose owner permission bits should be ensured.
    """
    try:
        st = os.lstat(entry_path)
    except OSError:
        return
    if stat.S_ISDIR(st.st_mode):
        needed = stat.S_IRWXU
    elif stat.S_ISREG(st.st_mode):
        needed = stat.S_IRUSR | stat.S_IWUSR
    else:
        return
    current = stat.S_IMODE(st.st_mode)
    if (current & needed) != needed:
        try:
            os.chmod(entry_path, current | needed)
        except OSError:
            pass


def _make_tree_writable(path: str) -> None:
    """Grants owner traversal and write permissions across a directory tree.

    Args:
        path: Root directory path to make writable and traversable.
    """
    _ensure_writable(path)
    for dirpath, dirnames, filenames in os.walk(path, topdown=True, followlinks=False):
        for dirname in dirnames:
            _ensure_writable(os.path.join(dirpath, dirname))
        for filename in filenames:
            _ensure_writable(os.path.join(dirpath, filename))


def _rmtree_with_permissions(path: str) -> None:
    """Removes a directory tree after fixing read-only permissions.

    Args:
        path: Directory path to remove.
    """
    _make_tree_writable(path)
    errors: list[tuple[str, BaseException]] = []

    def _record_exc(_func: object, fpath: str, exc: BaseException) -> None:
        if isinstance(exc, FileNotFoundError):
            return
        errors.append((fpath, exc))

    if sys.version_info >= (3, 12):
        shutil.rmtree(path, onexc=_record_exc)
    else:

        def _record_err(
            func: object,
            fpath: str,
            exc_info: tuple[object, BaseException, object],
        ) -> None:
            _record_exc(func, fpath, exc_info[1])

        shutil.rmtree(path, onerror=_record_err)

    if errors:
        sorted_errors = sorted(errors, key=lambda item: item[0])
        details = "\n".join(f"  {fpath}: {exc}" for fpath, exc in sorted_errors)
        log_warn(f"Failed to completely remove {path}:\n{details}")


async def remove_directory_safely(path: str) -> bool:
    """Removes a directory tree, making read-only entries writable.

    Args:
        path: Directory or symlink path to remove.

    Returns:
        True if the path no longer exists on disk, False otherwise.
    """
    if os.path.islink(path):
        try:
            os.unlink(path)
            return True
        except OSError as exc:
            log_warn(f"Failed to remove symlink {path}: {exc}")
            return False

    if not os.path.exists(path):
        return True

    res = await run_command(["rm", "-rf", path])
    if res.returncode == 0 and not os.path.lexists(path):
        return True

    await asyncio.to_thread(_rmtree_with_permissions, path)
    return not os.path.lexists(path)


async def remove_git_worktree(
    main_repo: str, worktree_path: str, dry_run: bool = False
) -> bool:
    """Removes a Git worktree safely."""
    real_wt = os.path.realpath(worktree_path)
    real_main = os.path.realpath(main_repo)

    if real_wt == real_main:
        log_error(f"Cannot remove main repository worktree: {worktree_path}")
        return False

    if dry_run:
        log(f"  [Dry Run] Would remove Git worktree: {worktree_path}")
        return True

    # If current working directory is inside worktree, cd to main repo
    try:
        cwd = os.path.realpath(os.getcwd())
        if cwd == real_wt or cwd.startswith(real_wt + os.sep):
            os.chdir(real_main)
    except OSError:
        os.chdir(real_main)

    log(f"  Removing Git worktree: {worktree_path}")
    # --force discards untracked or uncommitted edits left in the finished worktree.
    res = await run_command(
        ["git", "-C", real_main, "worktree", "remove", "--force", real_wt]
    )
    if res.returncode != 0:
        log_warn(
            f"git worktree remove failed ({res.stderr.strip()}), removing directly..."
        )
        await remove_directory_safely(real_wt)
        await run_command(["git", "-C", real_main, "worktree", "prune"])

    return not os.path.exists(real_wt)


async def delete_local_branch(
    main_repo: str,
    branch: str,
    worktree_path: str | None = None,
    dry_run: bool = False,
) -> tuple[bool, str]:
    """Deletes a local Git branch, detaching HEAD in its target worktree first.

    Args:
        main_repo: Path to the primary Git repository.
        branch: Local branch name to delete.
        worktree_path: Target worktree path whose HEAD may be detached before
            deleting the branch, or None if no worktree is targeted.
        dry_run: If True, preview without mutating Git state.

    Returns:
        Tuple of (succeeded, status_message).
    """
    if is_protected_branch(branch):
        return False, f"Branch '{branch}' is protected and will not be deleted."

    branch_check = await run_command(
        [
            "git",
            "-C",
            main_repo,
            "show-ref",
            "--verify",
            "--quiet",
            f"refs/heads/{branch}",
        ]
    )
    if branch_check.returncode != 0:
        return True, f"Local branch '{branch}' does not exist."

    if dry_run:
        return True, f"[Dry Run] Would delete local branch '{branch}'."

    real_main = os.path.realpath(main_repo)
    real_target_wt = os.path.realpath(worktree_path) if worktree_path else None

    # Verify branch is not checked out in another worktree; detach target worktree.
    worktrees = await get_worktrees(main_repo)
    for wt in worktrees:
        if wt.branch != branch or not os.path.exists(wt.path):
            continue
        real_wt = os.path.realpath(wt.path)
        is_target_wt = real_wt == real_target_wt and real_wt != real_main
        if not is_target_wt:
            return (
                False,
                f"Branch '{branch}' is still checked out in active worktree: {wt.path}",
            )
        # Rewrite the HEAD symref directly to its resolved commit SHA (--no-deref) so
        # git branch -D can delete the branch without touching dirty worktree files.
        detach_res = await run_command(
            ["git", "-C", real_wt, "update-ref", "--no-deref", "HEAD", "HEAD"]
        )
        if detach_res.returncode != 0:
            return (
                False,
                f"Failed to detach HEAD in worktree '{wt.path}': "
                f"{detach_res.stderr.strip()}",
            )

    # -D force-deletes squash-merged or abandoned branches not ancestor-merged into main.
    res = await run_command(["git", "-C", main_repo, "branch", "-D", branch])
    if res.returncode == 0:
        return True, f"Deleted local branch '{branch}'."
    return False, f"Failed to delete local branch '{branch}': {res.stderr.strip()}"


async def delete_remote_branch(
    main_repo: str,
    branch: str,
    remote: str,
    dry_run: bool = False,
) -> tuple[bool, str]:
    """Deletes a branch on the remote fork."""
    if is_protected_branch(branch):
        return False, f"Branch '{branch}' is protected and will not be deleted."

    if remote in _PROTECTED_REMOTES:
        return (
            False,
            f"Remote '{remote}' is protected (canonical upstream). Branch will not be deleted.",
        )

    exists = await remote_branch_exists(main_repo, remote, branch)
    if not exists:
        return True, f"Remote branch '{branch}' does not exist on '{remote}'."

    if dry_run:
        return (
            True,
            f"[Dry Run] Would delete remote branch '{branch}' on remote '{remote}'.",
        )

    res = await run_command(
        ["git", "-C", main_repo, "push", remote, "--delete", branch],
        timeout=_GIT_PUSH_DELETE_TIMEOUT_SECONDS,
    )
    if res.returncode == 0:
        return True, f"Deleted remote branch '{branch}' from '{remote}'."
    return (
        False,
        f"Failed to delete remote branch '{branch}' on '{remote}': {res.stderr.strip()}",
    )


async def build_cleanup_target(
    main_repo: str,
    worktree_path: str | None,
    branch: str | None,
    remote: str | None = None,
) -> CleanupTarget:
    """Assembles all resources associated with a target worktree/branch."""
    target = CleanupTarget(
        worktree_path=worktree_path,
        branch=branch,
        remote=remote,
    )

    if worktree_path:
        real_wt = os.path.realpath(worktree_path)
        real_main = os.path.realpath(main_repo)
        target.is_main_worktree = real_wt == real_main
        target.bazel_output_bases = find_bazel_output_bases(worktree_path)

    if branch:
        if not target.remote:
            target.remote = await get_push_remote_for_branch(main_repo, branch)
        if target.remote and target.remote not in _PROTECTED_REMOTES:
            target.remote_branch_exists = await remote_branch_exists(
                main_repo, target.remote, branch
            )

    return target


async def execute_cleanup_target(
    main_repo: str,
    target: CleanupTarget,
    leave_bazel_output_base: bool = False,
    leave_worktree: bool = False,
    leave_branch: bool = False,
    leave_remote: bool = False,
    dry_run: bool = False,
) -> tuple[list[str], bool]:
    """Executes cleanup on a single target and returns deleted resources and success."""
    log(f"\nCleaning up target resources for: {target.worktree_path or target.branch}")
    deleted: list[str] = []
    succeeded = True

    if target.is_main_worktree:
        log_error(
            "Target is the main repository! Refusing to clean up main repository."
        )
        return deleted, False

    # 1. Clean up Bazel output bases
    if not leave_bazel_output_base and target.bazel_output_bases:
        log("1. Cleaning up Bazel output bases:")
        for ob in target.bazel_output_bases:
            size_str = await get_path_size_human(ob)
            log(f"  - Output base: {ob} ({size_str})")
            if await shutdown_and_remove_bazel_output_base(ob, dry_run=dry_run):
                deleted.append(f"Bazel output base: {ob} ({size_str})")
            else:
                succeeded = False
    elif leave_bazel_output_base:
        log("1. Leaving Bazel output base intact.")
    else:
        log("1. No associated Bazel output bases found.")

    # 2. Clean up remote Git branch before detaching/deleting local branch
    remote_succeeded = True
    if (
        not leave_remote
        and target.branch
        and target.remote
        and target.remote_branch_exists
    ):
        log(f"2. Cleaning up remote branch '{target.branch}' on '{target.remote}':")
        success, msg = await delete_remote_branch(
            main_repo, target.branch, target.remote, dry_run=dry_run
        )
        if success:
            log(f"  {msg}")
            deleted.append(f"Remote branch: {target.remote}/{target.branch}")
        else:
            log_warn(f"  {msg}")
            remote_succeeded = False
            succeeded = False
    elif leave_remote:
        log("2. Leaving remote branch intact.")
    elif target.branch and target.remote:
        log(f"2. Remote branch '{target.branch}' not present on '{target.remote}'.")

    # 3. Clean up local Git branch
    if not leave_branch and target.branch:
        log(f"3. Cleaning up local branch '{target.branch}':")
        if not remote_succeeded and target.worktree_path:
            log_warn(
                "  Skipping local branch deletion because remote branch cleanup failed."
            )
        else:
            success, msg = await delete_local_branch(
                main_repo,
                target.branch,
                worktree_path=target.worktree_path,
                dry_run=dry_run,
            )
            if success:
                log(f"  {msg}")
                deleted.append(f"Local branch: {target.branch}")
            else:
                log_warn(f"  {msg}")
                succeeded = False
    elif leave_branch:
        log("3. Leaving local branch intact.")
    else:
        log("3. No local branch specified.")

    # 4. Clean up Git worktree last, and only if all other cleanup succeeded
    if not leave_worktree and target.worktree_path:
        log("4. Cleaning up Git worktree:")
        if not succeeded:
            log_warn(
                "  Skipping Git worktree removal because earlier cleanup steps failed."
            )
        elif await remove_git_worktree(
            main_repo, target.worktree_path, dry_run=dry_run
        ):
            deleted.append(f"Git worktree: {target.worktree_path}")
        else:
            succeeded = False
    elif leave_worktree:
        log("4. Leaving Git worktree directory on disk.")
    else:
        log("4. No worktree directory to remove.")

    return deleted, succeeded


def format_done_title(current_title: str) -> str:
    """Prepends 'done ' to a conversation title and truncates to max length."""
    cleaned = " ".join(current_title.splitlines()).strip()
    if not cleaned:
        return _DONE_TITLE_PREFIX.strip()

    if cleaned.lower().startswith(_DONE_TITLE_PREFIX):
        prefixed = _DONE_TITLE_PREFIX + cleaned[len(_DONE_TITLE_PREFIX) :].lstrip()
    else:
        prefixed = f"{_DONE_TITLE_PREFIX}{cleaned}"

    return prefixed[:_CONVERSATION_TITLE_MAX_LENGTH].rstrip()


def prefix_conversation_title(
    conversation_id: str,
    ls_address: str,
    csrf_header_value: str,
    dry_run: bool,
) -> None:
    """Prepends 'done ' to the active conversation title via the Language Server."""
    headers = {
        "Content-Type": "application/json",
        "x-codeium-csrf-token": csrf_header_value,
    }
    list_url = f"http://{ls_address}/{_GET_TRAJECTORIES_METHOD}"
    list_req = urllib.request.Request(
        list_url,
        data=b"{}",
        headers=headers,
    )
    try:
        with urllib.request.urlopen(list_req, timeout=_LS_RPC_TIMEOUT_SECONDS) as resp:
            payload = json.loads(resp.read().decode("utf-8"))
    except (urllib.error.URLError, json.JSONDecodeError, OSError) as exc:
        log_warn(f"Failed to query conversation title: {exc}")
        return

    summaries = payload.get("trajectorySummaries") or {}
    entry = summaries.get(conversation_id) or {}
    annotations = entry.get("annotations") or {}
    current_title = annotations.get("title") or entry.get("summary") or ""
    if not current_title:
        return

    new_title = format_done_title(current_title)
    if new_title == current_title:
        return

    if dry_run:
        log(f"  [Dry Run] Would rename conversation to: {new_title}")
        return

    update_url = f"http://{ls_address}/{_UPDATE_ANNOTATIONS_METHOD}"
    update_body = json.dumps(
        {
            "cascadeId": conversation_id,
            "annotations": {"title": new_title},
            "mergeAnnotations": True,
        }
    ).encode("utf-8")
    update_req = urllib.request.Request(
        update_url,
        data=update_body,
        headers=headers,
    )
    try:
        with urllib.request.urlopen(
            update_req, timeout=_LS_RPC_TIMEOUT_SECONDS
        ) as resp:
            resp.read()
        log(f"Renamed conversation to: {new_title}")
    except (urllib.error.URLError, OSError) as exc:
        log_warn(f"Failed to rename conversation: {exc}")


async def list_resources(main_repo: str) -> None:
    """Lists all worktrees and their associated resources."""
    worktrees = await get_worktrees(main_repo)
    log(f"Found {len(worktrees)} Git worktrees in {main_repo}:\n")
    for wt in worktrees:
        kind = " [MAIN REPO]" if wt.is_main else ""
        branch_str = f" (branch: {wt.branch})" if wt.branch else " (detached HEAD)"
        log(f"* {wt.path}{kind}{branch_str}")
        obs = find_bazel_output_bases(wt.path)
        if obs:
            for ob in obs:
                size_str = await get_path_size_human(ob)
                log(f"    - Bazel output base: {ob} ({size_str})")
        else:
            log("    - No Bazel output base found.")


class CleanupError(Exception):
    """Raised when workspace or Git discovery fails."""


@dataclasses.dataclass
class WorktreeInfo:
    """Information about a Git worktree."""

    # Absolute filesystem path to the worktree root.
    path: str
    # Commit SHA currently at HEAD in the worktree.
    head: str
    # Checked-out short branch name, or None when HEAD is detached.
    branch: str | None
    # Whether this entry represents the primary Git repository worktree.
    is_main: bool


@dataclasses.dataclass
class CleanupTarget:
    """Target resources identified for cleanup."""

    # Filesystem path to the target Git worktree, or None for branch-only cleanup.
    worktree_path: str | None = None
    # Local Git branch name associated with the target, if any.
    branch: str | None = None
    # Git remote name used for remote branch cleanup, if any.
    remote: str | None = None
    # Whether the target branch currently exists on the configured remote.
    remote_branch_exists: bool = False
    # Bazel output base directories linked to the target worktree.
    bazel_output_bases: list[str] = dataclasses.field(default_factory=list)
    # Whether worktree_path points to the primary Git repository worktree.
    is_main_worktree: bool = False


async def async_main(argv: Sequence[str]) -> None:
    """Runs the workspace cleanup CLI workflow."""
    args = parse_args(argv)
    main_repo = await get_main_repo()

    if args.list:
        await list_resources(main_repo)
        return

    worktrees = await get_worktrees(main_repo)
    targets: list[CleanupTarget] = []

    # If branches were explicitly provided
    if args.branches:
        for branch in args.branches:
            wt_path = None
            for wt in worktrees:
                if wt.branch == branch:
                    wt_path = wt.path
                    break
            target = await build_cleanup_target(
                main_repo, wt_path, branch, remote=args.remote
            )
            targets.append(target)

    # If worktree was explicitly provided
    elif args.worktree:
        real_target = os.path.realpath(args.worktree)
        found_branch = None
        for wt in worktrees:
            if os.path.realpath(wt.path) == real_target:
                found_branch = wt.branch
                break
        target = await build_cleanup_target(
            main_repo, args.worktree, found_branch, remote=args.remote
        )
        targets.append(target)

    # Otherwise default to current worktree
    else:
        curr_wt = await get_current_worktree()
        if not curr_wt:
            log_error(
                "Could not determine current worktree. "
                "Specify --worktree or --branches."
            )
            sys.exit(1)

        real_curr = os.path.realpath(curr_wt)
        real_main = os.path.realpath(main_repo)
        if real_curr == real_main:
            log_error(
                "Currently inside the main repository. Refusing to clean up main repository.\n"
                "Specify --worktree or --branches."
            )
            sys.exit(1)

        found_branch = None
        for wt in worktrees:
            if os.path.realpath(wt.path) == real_curr:
                found_branch = wt.branch
                break

        target = await build_cleanup_target(
            main_repo, curr_wt, found_branch, remote=args.remote
        )
        targets.append(target)

    if not targets:
        log_error("No valid targets identified for cleanup.")
        sys.exit(1)

    # Show preview
    for target in targets:
        log("\nIdentified resources for cleanup:")
        if target.worktree_path:
            log(f"  Worktree directory: {target.worktree_path}")
        if target.bazel_output_bases:
            for ob in target.bazel_output_bases:
                size_str = await get_path_size_human(ob)
                log(f"  Bazel output base:  {ob} ({size_str})")
        else:
            log("  Bazel output base:  None found")
        if target.remote and target.remote_branch_exists:
            log(f"  Remote branch:      {target.remote}/{target.branch}")
        if target.branch:
            log(f"  Local branch:       {target.branch}")

    if not args.force and not args.dry_run and sys.stdin.isatty():
        confirm = input("\nProceed with cleanup? [y/N]: ").strip()
        if confirm.lower() not in ("y", "yes"):
            log("Aborted.")
            return

    deleted_resources: list[str] = []
    all_succeeded = True
    for target in targets:
        deleted, succeeded = await execute_cleanup_target(
            main_repo,
            target,
            leave_bazel_output_base=args.leave_bazel_output_base,
            leave_worktree=args.leave_worktree,
            leave_branch=args.leave_branch,
            leave_remote=args.leave_remote,
            dry_run=args.dry_run,
        )
        deleted_resources.extend(deleted)
        if not succeeded:
            all_succeeded = False

    summary_header = (
        "\nResources that would be deleted (dry run):"
        if args.dry_run
        else "\nDeleted resources:"
    )
    log(summary_header)
    if deleted_resources:
        for resource in deleted_resources:
            log(f"  - {resource}")
    else:
        log("  None")

    if not all_succeeded:
        log_error("Cleanup finished with errors.")
        sys.exit(1)

    conversation_id = os.environ.get("ANTIGRAVITY_CONVERSATION_ID", "").strip()
    ls_address = os.environ.get("ANTIGRAVITY_LS_ADDRESS", "").strip()
    csrf_header_value = os.environ.get("ANTIGRAVITY_CSRF_TOKEN", "").strip()
    if conversation_id and ls_address and csrf_header_value:
        prefix_conversation_title(
            conversation_id=conversation_id,
            ls_address=ls_address,
            csrf_header_value=csrf_header_value,
            dry_run=args.dry_run,
        )

    log("\nCleanup completed.")


def main() -> None:
    """Main CLI entrypoint."""
    try:
        asyncio.run(async_main(sys.argv[1:]))
    except CleanupError as exc:
        log_error(str(exc))
        sys.exit(1)


if __name__ == "__main__":
    main()
