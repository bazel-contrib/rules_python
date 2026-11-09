#!/usr/bin/env python3
"""Runs google/keep-sorted in lint mode across tracked files.

Usage:
  check_keep_sorted.py /path/to/keep-sorted
"""

from __future__ import annotations

import argparse
import asyncio
import json
import os
import subprocess
import sys
from collections.abc import Sequence
from pathlib import Path

# Cap file arguments per subprocess invocation well below Linux ARG_MAX (2 MiB).
FILES_PER_BATCH = 200
_MAX_CONCURRENCY = os.cpu_count() or 4


def _parse_args(argv: list[str]) -> Path:
    """Parses CLI arguments and returns the `keep-sorted` executable path."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "binary",
        type=Path,
        help="Path to the keep-sorted executable.",
    )
    args = parser.parse_args(argv)
    return args.binary


def _format_subprocess_error(
    prefix: str, proc: subprocess.CompletedProcess[str]
) -> str:
    """Formats a failed subprocess result with demarcated stdout/stderr."""
    return (
        f"{prefix} (exit {proc.returncode}):\n"
        f"==================== STDOUT BEGIN ====================\n"
        f"{proc.stdout}"
        f"==================== STDOUT END ====================\n"
        f"==================== STDERR BEGIN ====================\n"
        f"{proc.stderr}"
        f"==================== STDERR END ===================="
    )


async def _run_process(
    cmd: Sequence[str], *, cwd: Path | None = None
) -> subprocess.CompletedProcess[str]:
    """Runs `cmd` and captures UTF-8 stdout and stderr."""
    proc = await asyncio.create_subprocess_exec(
        *cmd,
        cwd=cwd,
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.PIPE,
    )
    stdout_bytes, stderr_bytes = await proc.communicate()
    assert proc.returncode is not None  # type assert
    return subprocess.CompletedProcess(
        args=list(cmd),
        returncode=proc.returncode,
        stdout=stdout_bytes.decode("utf-8"),
        stderr=stderr_bytes.decode("utf-8"),
    )


def _filter_regular_files(repo_root: Path, raw_entries: Sequence[str]) -> list[str]:
    """Filters NUL-split git paths down to existing non-symlink regular files."""
    tracked: list[str] = []
    for rel_path in raw_entries:
        if not rel_path:
            continue
        full_path = repo_root / rel_path
        if full_path.is_file() and not full_path.is_symlink():
            tracked.append(rel_path)
    return tracked


async def list_tracked_files(repo_root: Path) -> list[str]:
    """Lists existing regular files tracked by git under `repo_root`.

    Args:
        repo_root: Repository root directory.

    Returns:
        Paths relative to `repo_root`.
    """
    # -z (no long form) NUL-delimits paths without quoting special characters.
    proc = await _run_process(["git", "ls-files", "-z"], cwd=repo_root)
    if proc.returncode != 0:
        raise RuntimeError(_format_subprocess_error("git ls-files failed", proc))
    raw_entries = proc.stdout.split("\0")
    return await asyncio.to_thread(_filter_regular_files, repo_root, raw_entries)


def _format_finding(finding: dict[str, object]) -> str:
    """Formats a single `keep-sorted --mode=lint` JSON finding line.

    Args:
        finding: Parsed JSON finding object with `path`, `lines`, and `message`.

    Returns:
        Formatted `<path>:<lines>: <message>` string with `path` relative to the
        repository root.
    """
    path = str(finding["path"])
    lines_obj = finding["lines"]
    if not isinstance(lines_obj, dict):
        raise ValueError(f"Unexpected 'lines' payload in finding: {finding!r}")
    start = int(lines_obj["start"])
    end = int(lines_obj["end"])
    message = str(finding["message"])
    if start == end:
        location = f"{path}:{start}"
    else:
        location = f"{path}:{start}-{end}"
    return f"{location}: {message}"


async def _lint_batch(
    binary: Path,
    repo_root: Path,
    batch: Sequence[str],
    semaphore: asyncio.Semaphore,
) -> list[str]:
    """Runs `keep-sorted --mode=lint` on a single batch of files."""
    async with semaphore:
        # --mode=lint checks without modifying files and emits JSON findings on stdout.
        proc = await _run_process(
            [str(binary), "--mode=lint", "--", *batch],
            cwd=repo_root,
        )
    if proc.returncode == 0:
        return []
    stdout = proc.stdout.strip()
    if not stdout:
        raise RuntimeError(_format_subprocess_error("keep-sorted failed", proc))
    try:
        findings = json.loads(stdout)
    except json.JSONDecodeError as err:
        raise RuntimeError(
            _format_subprocess_error("Failed to parse keep-sorted JSON output", proc)
        ) from err
    if not isinstance(findings, list) or not findings:
        raise RuntimeError(
            _format_subprocess_error("Unexpected keep-sorted output", proc)
        )
    batch_failures: list[str] = []
    for item in findings:
        if not isinstance(item, dict):
            raise RuntimeError(f"Unexpected finding entry: {item!r}")
        batch_failures.append(_format_finding(item))
    return batch_failures


async def lint_files(binary: Path, repo_root: Path, files: Sequence[str]) -> list[str]:
    """Runs `keep-sorted --mode=lint` concurrently across bounded batches.

    Args:
        binary: Path to the `keep-sorted` executable.
        repo_root: Repository root directory from which relative `files` resolve.
        files: File paths relative to `repo_root`.

    Returns:
        Unsorted list of formatted failure strings (empty when all files pass).
    """
    semaphore = asyncio.Semaphore(_MAX_CONCURRENCY)
    batches = [
        files[offset : offset + FILES_PER_BATCH]
        for offset in range(0, len(files), FILES_PER_BATCH)
    ]
    results = await asyncio.gather(
        *(_lint_batch(binary, repo_root, batch, semaphore) for batch in batches)
    )
    failures: list[str] = []
    for batch_result in results:
        failures.extend(batch_result)
    return failures


async def _repo_root() -> Path:
    """Returns the git repository root directory."""
    proc = await _run_process(["git", "rev-parse", "--show-toplevel"])
    if proc.returncode != 0:
        raise RuntimeError(_format_subprocess_error("git rev-parse failed", proc))
    return Path(proc.stdout.strip())


async def async_main(argv: list[str]) -> int:
    """Async CLI entry point."""
    binary = _parse_args(argv).resolve()
    repo_root = await _repo_root()
    files = await list_tracked_files(repo_root)
    failures = await lint_files(binary, repo_root, files)
    if not failures:
        print(f"Checked {len(files)} tracked files: all keep-sorted blocks sorted.")
        return 0

    for line in sorted(failures):
        print(line, file=sys.stderr)
    return 1


def main(argv: list[str]) -> int:
    """Synchronous CLI entry point."""
    return asyncio.run(async_main(argv))


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
