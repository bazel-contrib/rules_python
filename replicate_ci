#!/usr/bin/env python3

import argparse
import os
import shlex
import subprocess
import sys

import yaml


def parse_args():
    parser = argparse.ArgumentParser(
        description="Replicate and emulate BazelCI job configurations from presubmit.yml."
    )
    parser.add_argument(
        "job",
        help="The key or name of the CI job to emulate (e.g., ubuntu_workspace or 'Default: Ubuntu, workspace').",
    )
    return parser.parse_args()


def run_cmd(cmd, cwd=None, env=None, shell=False):
    if shell:
        cmd_str = cmd if isinstance(cmd, str) else " ".join(cmd)
    else:
        cmd_str = shlex.join(cmd) if isinstance(cmd, list) else str(cmd)

    print(f"\n🚀 Executing: {cmd_str}")
    if cwd and cwd != os.getcwd():
        print(f"📁 Directory: {cwd}")
    if env and "USE_BAZEL_VERSION" in env:
        print(f"🔧 Bazel Version: {env['USE_BAZEL_VERSION']}")

    res = subprocess.run(cmd, cwd=cwd, env=env, shell=shell)
    if res.returncode != 0:
        print(
            f"\n❌ Command failed with return code {res.returncode}: {cmd_str}",
            file=sys.stderr,
        )
        sys.exit(res.returncode)


def resolve_bazel_version(task_bazel):
    if not task_bazel or task_bazel.startswith("${{"):
        return None
    return task_bazel


def main():
    args = parse_args()

    presubmit_path = ".bazelci/presubmit.yml"
    if not os.path.exists(presubmit_path):
        print(
            f"❌ Error: Presubmit file not found at '{presubmit_path}'",
            file=sys.stderr,
        )
        sys.exit(1)

    with open(presubmit_path) as f:
        presubmit = yaml.safe_load(f)

    tasks = presubmit.get("tasks", {})
    if not tasks:
        print(
            f"❌ Error: No tasks found in '{presubmit_path}'",
            file=sys.stderr,
        )
        sys.exit(1)

    # Match by key or by name
    job_key = None
    if args.job in tasks:
        job_key = args.job
    else:
        for key, config in tasks.items():
            if config.get("name") == args.job:
                job_key = key
                break

    if not job_key:
        print(
            f"❌ Error: CI job '{args.job}' not found in '{presubmit_path}'\n",
            file=sys.stderr,
        )
        print("📋 Available CI Job Keys:", file=sys.stderr)
        for key in sorted(tasks.keys()):
            name = tasks[key].get("name", key)
            print(f"  • {key}  ({name})", file=sys.stderr)
        sys.exit(1)

    task = tasks[job_key]
    job_name = task.get("name", job_key)
    print(f"🎯 Replicating CI Job: {job_key}  ('{job_name}')")

    # Setup working directory
    repo_root = os.path.abspath(os.path.dirname(__file__))
    cwd = repo_root
    if "working_directory" in task:
        cwd = os.path.join(repo_root, task["working_directory"])
        if not os.path.exists(cwd):
            print(
                f"❌ Error: working_directory '{task['working_directory']}' does not exist at '{cwd}'",
                file=sys.stderr,
            )
            sys.exit(1)

    # Setup environment
    env = os.environ.copy()
    bzl_version = resolve_bazel_version(task.get("bazel"))
    if bzl_version:
        env["USE_BAZEL_VERSION"] = bzl_version

    # Execute pre-commands
    is_windows = sys.platform.startswith("win")
    pre_cmds = task.get("batch_commands" if is_windows else "shell_commands", [])
    for pre_cmd in pre_cmds:
        run_cmd(pre_cmd, cwd=cwd, env=env, shell=True)

    # Execute Build Targets
    build_targets = task.get("build_targets", [])
    if build_targets:
        build_flags = task.get("build_flags", [])
        cmd = ["bazel", "build"] + build_flags + ["--"] + build_targets
        run_cmd(cmd, cwd=cwd, env=env)

    # Execute Test Targets
    test_targets = task.get("test_targets", [])
    if test_targets:
        test_flags = task.get("test_flags", [])
        cmd = ["bazel", "test"] + test_flags + ["--"] + test_targets
        run_cmd(cmd, cwd=cwd, env=env)

    # Execute Coverage Targets
    coverage_targets = task.get("coverage_targets", [])
    if coverage_targets:
        coverage_flags = task.get("test_flags", [])
        cmd = ["bazel", "coverage"] + coverage_flags + ["--"] + coverage_targets
        run_cmd(cmd, cwd=cwd, env=env)

    print(f"\n🎉 Successfully replicated CI Job: {job_key}")


if __name__ == "__main__":
    main()
