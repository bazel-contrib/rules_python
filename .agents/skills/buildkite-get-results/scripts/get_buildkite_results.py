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
        description="Gets Buildkite build results using the 'bk' CLI."
    )
    parser.add_argument(
        "pr", help="PR number, Build URL, or Build ID (org/pipeline/build)"
    )
    parser.add_argument(
        "--jobs",
        help="Glob-style filtering of job names to display or download",
    )
    parser.add_argument("--download", action="store_true", help="Download job logs")
    args = parser.parse_args()

    check_cli("bk", "https://github.com/buildkite/cli")

    target = args.pr
    if target.isdigit() and len(target) < 10:
        print(f"🔍 Inspecting PR #{target} via gh to find Buildkite URL...")
        target = get_build_url_from_pr(target)

    build_id = normalize_build_target(target)
    print(f"🚀 Querying Buildkite for build: {build_id}\n")

    # Run bk build view
    res = subprocess.run(["bk", "build", "view", build_id])
    if res.returncode != 0:
        print(
            f"❌ Failed to view build '{build_id}' via 'bk' CLI.",
            file=sys.stderr,
        )
        sys.exit(res.returncode)

    if args.download:
        print(f"\n📥 Downloading logs for build: {build_id}")
        dl_res = subprocess.run(["bk", "build", "download", build_id])
        if dl_res.returncode != 0:
            print(
                "⚠️ 'bk build download' failed or not supported. Try using 'bk job log <job-id>' for specific jobs."
            )


if __name__ == "__main__":
    main()
