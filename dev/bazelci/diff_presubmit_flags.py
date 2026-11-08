"""Shows how a presubmit.yml change alters each BazelCI task's flags.

Usage:
    bazel run //dev/bazelci:diff_presubmit_flags
    bazel run //dev/bazelci:diff_presubmit_flags -- --base=HEAD~1
    bazel run //dev/bazelci:diff_presubmit_flags -- --flag=--config=ci

It reads `.bazelci/presubmit.yml` from the workspace and, through `git show`,
from the `--base` ref. For each task, it prints the `build_flags` and
`test_flags` that were added or removed, as BazelCI passes them to Bazel after
resolving YAML merges. With `--flag`, it instead lists the tasks in the
workspace's presubmit.yml that pass that flag.
"""

from __future__ import annotations

import argparse
import os
import subprocess
import sys
from pathlib import Path

from dev.bazelci import presubmit_flags


def _git_show(workspace: Path, spec: str) -> str:
    try:
        result = subprocess.run(
            ["git", "show", spec],
            cwd=workspace,
            capture_output=True,
            text=True,
            check=True,
        )
    except subprocess.CalledProcessError as e:
        e.add_note(
            "==================== STDOUT BEGIN ====================\n"
            f"{e.stdout}"
            "==================== STDOUT END ====================\n"
            "==================== STDERR BEGIN ====================\n"
            f"{e.stderr}"
            "==================== STDERR END ===================="
        )
        raise
    return result.stdout


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument(
        "--base",
        default="upstream/main",
        help="Git ref whose presubmit.yml to compare with (default: %(default)s).",
    )
    mode.add_argument(
        "--flag",
        help="List the tasks that pass this flag, e.g. --flag=--config=ci.",
    )
    args = parser.parse_args(argv)

    workspace = Path(os.environ["BUILD_WORKSPACE_DIRECTORY"])
    presubmit = workspace / presubmit_flags.PRESUBMIT_PATH
    workspace_tasks = presubmit_flags.load_tasks(presubmit.read_text(encoding="utf-8"))

    if args.flag:
        lines = presubmit_flags.tasks_with_flag(workspace_tasks, args.flag)
        print("\n".join(lines) if lines else f"No task passes {args.flag}.")
        return 0

    base_text = _git_show(workspace, f"{args.base}:{presubmit_flags.PRESUBMIT_PATH}")
    base_tasks = presubmit_flags.load_tasks(base_text)
    lines = presubmit_flags.diff_tasks(base_tasks, workspace_tasks)
    print("\n".join(lines) if lines else f"No task's flags differ from {args.base}.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
