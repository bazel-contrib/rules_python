"""Git repository resolution, remote matching, and PR worktree setup."""

from __future__ import annotations

import asyncio
import logging
import re
from collections.abc import Sequence
from pathlib import Path
from urllib.parse import urlsplit

from fetch_pr_queue import (
    format_subprocess_error,
    is_transient_error,
    retry_async,
    run_subprocess_async,
    sanitize_log_text,
)
from ls_client import collect_project_paths_from_disk, collect_project_paths_from_ls
from state_store import PrQueueError

# =============================================================================
# 1. Global Constants
# =============================================================================

# Git fetch over HTTPS/SSH can take noticeable time on cold refs.
_GIT_FETCH_TIMEOUT_SECONDS = 60
# Worktree creation checks out the full repo tree, so allow headroom on slow disks.
_GIT_LOCAL_TIMEOUT_SECONDS = 30
# Only permit safe Git ref characters (disallowing whitespace, `:`, `..`, `-`, etc.).
_SAFE_GIT_REF_RE = re.compile(r"\A[A-Za-z0-9._/@+-]+\Z")
_REMOTE_SCHEMES = frozenset(
    {
        # keep-sorted start
        "git",
        "http",
        "https",
        "ssh",
        # keep-sorted end
    }
)

_LOGGER = logging.getLogger("pr_queue.git")


# =============================================================================
# 2. Functions
# =============================================================================


async def _run_git(
    repo_dir: Path,
    args: Sequence[str],
    *,
    timeout_seconds: int = _GIT_LOCAL_TIMEOUT_SECONDS,
) -> str:
    """Runs a git subprocess under asyncio and returns stdout."""
    label = f"git {' '.join(args[:3])}"
    returncode, stdout, stderr = await run_subprocess_async(
        # -C sets the working repository directory.
        ["git", "-C", str(repo_dir), *args],
        label=label,
        timeout_seconds=timeout_seconds,
        error_cls=PrQueueError,
        missing_binary_message="`git` executable was not found on PATH.",
    )
    if returncode != 0:
        raise PrQueueError(format_subprocess_error(label, returncode, stdout, stderr))
    return stdout


async def _run_git_fetch(repo_dir: Path, args: Sequence[str]) -> str:
    """Runs `git fetch` with bounded retries on transient transport errors."""
    label = f"git fetch {' '.join(args[:2])}"
    return await retry_async(
        lambda: _run_git(repo_dir, args, timeout_seconds=_GIT_FETCH_TIMEOUT_SECONDS),
        is_retryable=lambda exc: (
            isinstance(exc, PrQueueError) and is_transient_error(str(exc))
        ),
        label=label,
    )


async def _main_worktree_root(path: Path) -> Path | None:
    """Returns the primary repository checkout root for any path inside a repo."""
    if not path.exists():
        return None
    try:
        output = await _run_git(path, ["worktree", "list", "--porcelain"])
    except PrQueueError:
        return None
    for line in output.splitlines():
        if line.startswith("worktree "):
            return Path(line[len("worktree ") :].strip()).resolve()
    return None


async def _remote_urls(repo_dir: Path) -> dict[str, str]:
    """Maps git remote names to their configured URLs for repo_dir."""
    try:
        # Read raw remote.<name>.url entries so `url.*.insteadOf` transport
        # rewrites still match the canonical GitHub owner/repo slug.
        output = await _run_git(
            repo_dir, ["config", "--get-regexp", r"^remote\..+\.url$"]
        )
    except PrQueueError:
        return {}
    remotes: dict[str, str] = {}
    for line in output.splitlines():
        parts = line.split(None, 1)
        if len(parts) != 2:
            continue
        key, url = parts
        if not (key.startswith("remote.") and key.endswith(".url")):
            continue
        name = key[len("remote.") : -len(".url")]
        if name and name not in remotes:
            remotes[name] = url.strip()
    return remotes


def remote_matches_repo(remote_url: str, repo: str) -> bool:
    """Returns whether remote_url points to `github.com/<owner>/<repo>`."""
    raw = remote_url.strip()
    target = repo.strip().lower()
    if not raw or not target:
        return False
    if "://" in raw:
        parsed = urlsplit(raw)
        if parsed.scheme.lower() not in _REMOTE_SCHEMES:
            return False
        if (parsed.hostname or "").lower() != "github.com":
            return False
        path = parsed.path.lstrip("/").rstrip("/")
    else:
        ssh_match = re.match(r"^(?:[^@/:]+@)?github\.com:(.+)$", raw, re.IGNORECASE)
        if not ssh_match:
            return False
        path = ssh_match.group(1).lstrip("/").rstrip("/")
    if path.lower().endswith(".git"):
        path = path[:-4]
    return path.lower() == target


def validate_git_ref_name(ref: str, *, label: str) -> str:
    """Validates a Git branch or remote name against shell/refspec metacharacters."""
    if any(ord(ch) < 32 or 127 <= ord(ch) <= 159 for ch in ref):
        raise PrQueueError(f"Invalid {label} `{sanitize_log_text(ref)}`.")
    clean = ref.strip()
    segments = clean.split("/")
    if (
        not clean
        or clean == "@"
        or clean.startswith("-")
        or ".." in clean
        or "@{" in clean
        or not _SAFE_GIT_REF_RE.match(clean)
        or any(
            seg in ("", ".", "..")
            or seg.startswith(".")
            or seg.endswith(".")
            or seg.endswith(".lock")
            for seg in segments
        )
    ):
        raise PrQueueError(f"Invalid {label} `{clean}`.")
    return clean


def validate_base_ref(base_ref: str) -> str:
    """Validates and normalizes a PR base branch ref, defaulting blank to `main`."""
    return validate_git_ref_name(base_ref.strip() or "main", label="base branch")


async def _verify_configured_base_repo(configured_base_repo: str, repo: str) -> Path:
    explicit = Path(configured_base_repo.strip()).expanduser().resolve()
    if not explicit.exists():
        raise PrQueueError(f"Configured base repo path does not exist: {explicit}")
    root = await _main_worktree_root(explicit)
    if root is None:
        raise PrQueueError(f"Configured base repo is not a git repository: {explicit}")
    remotes = await _remote_urls(root)
    if not any(remote_matches_repo(url, repo) for url in remotes.values()):
        raise PrQueueError(
            f"Configured base repo `{root}` has no git remote matching `{repo}`."
        )
    return root


async def resolve_base_repo(
    configured_base_repo: str,
    repo: str,
    *,
    projects_file: Path,
    daemon_dir: Path,
    sidecar_dir: Path,
) -> Path:
    """Resolves the local main git repository matching the target GitHub repo.

    Args:
      configured_base_repo: Explicit user-configured checkout path, or `""`.
      repo: Target repository slug (`owner/name`).
      projects_file: Path to the IDE `projects.json` fallback file.
      daemon_dir: Directory containing Language Server daemon registration JSONs.
      sidecar_dir: Directory containing sidecar source files for ancestor lookup.

    Returns:
      Resolved Path to the primary local git checkout.
    """
    if configured_base_repo.strip():
        return await _verify_configured_base_repo(configured_base_repo, repo)

    # Check ancestors of the plugin directory first (fast in worktree checkouts).
    for ancestor in [sidecar_dir, *sidecar_dir.parents]:
        if (ancestor / ".git").exists():
            ancestor_root = await _main_worktree_root(ancestor)
            if ancestor_root is not None:
                ancestor_remotes = await _remote_urls(ancestor_root)
                if any(
                    remote_matches_repo(url, repo) for url in ancestor_remotes.values()
                ):
                    return ancestor_root
            break

    # Fall back from live LS ReadProjects to ~/.gemini/projects.json if needed.
    ls_paths, disk_paths = await asyncio.gather(
        collect_project_paths_from_ls(daemon_dir),
        asyncio.to_thread(collect_project_paths_from_disk, projects_file),
    )
    roots = await asyncio.gather(
        *(_main_worktree_root(candidate) for candidate in [*ls_paths, *disk_paths])
    )
    seen_roots: list[Path] = []
    for root in roots:
        if root is not None and root not in seen_roots:
            seen_roots.append(root)

    remote_maps = await asyncio.gather(*(_remote_urls(root) for root in seen_roots))
    for root, remotes in zip(seen_roots, remote_maps):
        if any(remote_matches_repo(url, repo) for url in remotes.values()):
            return root

    raise PrQueueError(
        f"Could not auto-detect a local git checkout for `{repo}`. "
        "Open the repository in the agent IDE or set `base_repo` in `config.json`."
    )


async def detect_remote_for_repo(main_repo: Path, repo: str) -> str:
    """Selects the git remote on main_repo matching `github.com/<repo>`."""
    remotes = await _remote_urls(main_repo)
    matching = [name for name, url in remotes.items() if remote_matches_repo(url, repo)]
    for preferred in ("upstream", "origin"):
        if preferred in matching:
            return preferred
    if matching:
        return matching[0]
    raise PrQueueError(f"No git remote matching `{repo}` configured in {main_repo}.")


async def _ensure_clean_worktree(
    main_repo: Path,
    worktree_path: Path,
    branch_name: str,
    head_sha: str,
) -> None:
    if worktree_path.exists():
        if not (worktree_path / ".git").exists():
            raise PrQueueError(
                f"Review path exists and is not a git worktree: {worktree_path}"
            )
        status = (await _run_git(worktree_path, ["status", "--porcelain"])).strip()
        if status:
            raise PrQueueError(
                f"Review worktree has uncommitted changes at {worktree_path}; "
                "clean or remove it before launching a fresh review."
            )
        # -B resets an existing review branch cleanly to the latest PR head SHA.
        await _run_git(worktree_path, ["checkout", "-B", branch_name, head_sha])
        return

    worktree_path.parent.mkdir(parents=True, exist_ok=True)
    # -B resets the review branch name if it already exists from an older review.
    await _run_git(
        main_repo,
        ["worktree", "add", "-B", branch_name, "--", str(worktree_path), head_sha],
    )


def _symlink_buildbuddy_rc(worktree_path: Path, buildbuddy_rc: Path) -> None:
    user_bazelrc = worktree_path / "user.bazelrc"
    # Symlink user's BuildBuddy cache config so Bazel runs match local builds.
    if (
        buildbuddy_rc.is_file()
        and (worktree_path / "MODULE.bazel").is_file()
        and not user_bazelrc.exists()
    ):
        try:
            user_bazelrc.symlink_to(buildbuddy_rc)
        except OSError as exc:
            _LOGGER.warning(
                "Could not symlink BuildBuddy config %s: %s",
                buildbuddy_rc,
                sanitize_log_text(exc),
            )


async def prepare_pr_worktree(
    main_repo: Path,
    pr_number: int,
    repo: str,
    base_ref: str = "main",
    *,
    worktrees_dir: Path,
    buildbuddy_rc: Path,
) -> tuple[Path, str, str]:
    """Creates or updates an isolated review worktree checked out at PR head.

    Args:
      main_repo: Primary local Git clone directory.
      pr_number: GitHub pull request number to check out.
      repo: Target repository slug (`owner/name`).
      base_ref: Base branch name (e.g., `main`).
      worktrees_dir: Base directory where per-repo review worktrees live.
      buildbuddy_rc: User BuildBuddy bazelrc symlinked into Bazel worktrees.

    Returns:
      Tuple `(worktree_path, head_sha, remote_name)`.
    """
    if isinstance(pr_number, bool) or pr_number <= 0:
        raise PrQueueError("`pr_number` must be a positive integer.")
    remote = validate_git_ref_name(
        await detect_remote_for_repo(main_repo, repo), label="git remote"
    )
    clean_base = validate_base_ref(base_ref)

    # Fetch base branch first so FETCH_HEAD remains available for PR ref next.
    # Force-update (+) the tracking ref in case the upstream branch rewrote history.
    await _run_git_fetch(
        main_repo,
        [
            "fetch",
            "--",
            remote,
            f"+refs/heads/{clean_base}:refs/remotes/{remote}/{clean_base}",
        ],
    )
    await _run_git_fetch(
        main_repo,
        ["fetch", "--", remote, f"pull/{pr_number}/head"],
    )
    head_sha = (await _run_git(main_repo, ["rev-parse", "FETCH_HEAD"])).strip()
    if not head_sha:
        raise PrQueueError(
            f"Fetched PR #{pr_number} head from `{remote}`, but FETCH_HEAD was empty."
        )

    await _run_git(main_repo, ["worktree", "prune"])
    worktree_path = (
        worktrees_dir / main_repo.name / f"review-pr-{pr_number}"
    ).resolve()
    branch_name = f"review-pr-{pr_number}"

    await _ensure_clean_worktree(main_repo, worktree_path, branch_name, head_sha)
    _symlink_buildbuddy_rc(worktree_path, buildbuddy_rc)
    return (worktree_path, head_sha, remote)
