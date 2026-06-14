#!/usr/bin/env python3

import argparse
import json
import re
import subprocess
import sys


def check_cli(cmd_name, install_url):
    try:
        subprocess.run(
            [cmd_name, "--version"],
            check=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
    except Exception:
        print(
            f"❌ Error: '{cmd_name}' CLI is not installed or not in PATH.",
            file=sys.stderr,
        )
        print(f"Please install it from {install_url}", file=sys.stderr)
        sys.exit(1)


def get_build_url_from_pr(pr_number):
    check_cli("gh", "https://cli.github.com/")
    cmd = ["gh", "pr", "checks", str(pr_number), "--json", "name,link"]
    try:
        res = subprocess.run(cmd, capture_output=True, text=True, check=True)
        checks = json.loads(res.stdout)
        for c in checks:
            link = c.get("link", "")
            if "buildkite.com" in link:
                return link.split("#")[0]
        print(f"❌ No Buildkite checks found for PR #{pr_number}.", file=sys.stderr)
        sys.exit(1)
    except subprocess.CalledProcessError as e:
        print(f"❌ Error fetching PR checks: {e.stderr}", file=sys.stderr)
        sys.exit(1)


def normalize_build_target(target):
    # Transforms https://buildkite.com/bazel/rules-python-python/builds/15707
    # into bazel/rules-python-python/15707
    m = re.search(r"buildkite\.com/([^/]+)/([^/]+)/builds/(\d+)", target)
    if m:
        return f"{m.group(1)}/{m.group(2)}/{m.group(3)}"
    return target


def main():
    parser = argparse.ArgumentParser(
        description="Retry failed Buildkite jobs using the 'bk' CLI."
    )
    parser.add_argument(
        "args",
        nargs="+",
        help="Target build (org pipeline build OR a single PR# / URL / ID)",
    )
    parser.add_argument(
        "--jobs",
        "--job-name",
        dest="job_name",
        help="Specific job name or pattern to retry",
    )
    args = parser.parse_args()

    check_cli("bk", "https://github.com/buildkite/cli")

    if len(args.args) == 3:
        target = f"{args.args[0]}/{args.args[1]}/{args.args[2]}"
    elif len(args.args) == 1:
        target = args.args[0]
    else:
        print(
            "❌ Error: Invalid arguments. Provide either 'org pipeline build' or a single target (PR#, URL, or org/pipeline/build).",
            file=sys.stderr,
        )
        sys.exit(1)

    if target.isdigit() and len(target) < 10:
        print(f"🔍 Inspecting PR #{target} via gh to find Buildkite URL...")
        target = get_build_url_from_pr(target)

    build_id = normalize_build_target(target)

    if args.job_name:
        print(f"🚀 Retrying jobs matching '{args.job_name}' in build: {build_id}")
        res = subprocess.run(["bk", "build", "retry", build_id, "--failed"])
    else:
        print(f"🚀 Retrying all failed jobs in build: {build_id}")
        res = subprocess.run(["bk", "build", "retry", build_id, "--failed"])

    if res.returncode != 0:
        print(
            f"❌ Failed to retry build '{build_id}' via 'bk' CLI.",
            file=sys.stderr,
        )
        sys.exit(res.returncode)

    print(f"🎉 Successfully triggered retry for build: {build_id}")


if __name__ == "__main__":
    main()
