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
    # into (org/pipeline, 15707)
    m = re.search(r"buildkite\.com/([^/]+/[^/]+)/builds/(\d+)", target)
    if m:
        return m.group(1), m.group(2)
    parts = target.split("/")
    if len(parts) == 3:
        return f"{parts[0]}/{parts[1]}", parts[2]
    elif len(parts) == 2:
        return parts[0], parts[1]
    return "bazel/rules-python-python", target


def retry_job_by_uuid(job_id):
    check_cli("bk", "https://github.com/buildkite/cli")
    print(f"🚀 Retrying individual job UUID: {job_id}")
    return subprocess.run(["bk", "job", "retry", job_id])


def retry_jobs_by_name(pipeline, build_number, job_pattern):
    check_cli("bk", "https://github.com/buildkite/cli")
    cmd = ["bk", "build", "view", str(build_number), "-p", pipeline, "--json"]
    try:
        res = subprocess.run(cmd, capture_output=True, text=True, check=True)
        data = json.loads(res.stdout)
        jobs = data.get("jobs", [])
        matched = []
        for j in jobs:
            name = j.get("name", "") or j.get("label", "")
            state = j.get("state", "")
            jid = j.get("id")
            if jid and (
                re.search(job_pattern, name, re.IGNORECASE)
                or job_pattern.lower() in name.lower()
            ):
                matched.append((jid, name, state))

        if not matched:
            print(
                f"⚠️ No jobs found matching pattern '{job_pattern}' in build #{build_number}",
                file=sys.stderr,
            )
            sys.exit(1)

        for jid, name, state in matched:
            print(f"🚀 Retrying job '{name}' (ID: {jid}, status: {state})...")
            subprocess.run(["bk", "job", "retry", jid])
    except Exception as e:
        print(f"❌ Error fetching build jobs: {e}", file=sys.stderr)
        sys.exit(1)


def main():
    parser = argparse.ArgumentParser(
        description="Retry Buildkite jobs individually using 'bk job retry' or rebuild the whole build using 'bk build rebuild'."
    )
    parser.add_argument(
        "args",
        nargs="+",
        help="Target build (PR#, Buildkite URL, or org/pipeline/build)",
    )
    parser.add_argument(
        "--jobs",
        "--job-name",
        dest="job_name",
        help="Specific job name or regex pattern to retry individually via 'bk job retry'",
    )
    parser.add_argument(
        "--job-id",
        dest="job_id",
        help="Specific job UUID to retry individually via 'bk job retry'",
    )
    parser.add_argument(
        "--rebuild",
        action="store_true",
        help="Rebuild the entire build afresh via 'bk build rebuild'",
    )
    args = parser.parse_args()

    check_cli("bk", "https://github.com/buildkite/cli")

    if args.job_id:
        res = retry_job_by_uuid(args.job_id)
        sys.exit(res.returncode)

    if len(args.args) == 3:
        target = f"{args.args[0]}/{args.args[1]}/{args.args[2]}"
    elif len(args.args) == 1:
        target = args.args[0]
    else:
        print(
            "❌ Error: Invalid arguments. Provide a single target (PR#, URL, or org/pipeline/build).",
            file=sys.stderr,
        )
        sys.exit(1)

    if target.isdigit() and len(target) < 10:
        print(f"🔍 Inspecting PR #{target} via gh to find Buildkite URL...")
        target = get_build_url_from_pr(target)

    pipeline, build_number = normalize_build_target(target)

    if args.job_name:
        retry_jobs_by_name(pipeline, build_number, args.job_name)
    elif args.rebuild:
        print(f"🚀 Rebuilding entire build #{build_number} for pipeline: {pipeline}")
        res = subprocess.run(
            ["bk", "build", "rebuild", build_number, "-p", pipeline, "--yes"]
        )
        sys.exit(res.returncode)
    else:
        # Default behavior: try job-level retries of failed jobs if any, otherwise rebuild
        cmd = [
            "bk",
            "build",
            "view",
            str(build_number),
            "-p",
            pipeline,
            "--json",
        ]
        try:
            res = subprocess.run(cmd, capture_output=True, text=True, check=True)
            data = json.loads(res.stdout)
            failed_jobs = [
                j
                for j in data.get("jobs", [])
                if j.get("state") in ("failed", "broken", "timed_out") and j.get("id")
            ]
            if failed_jobs:
                for j in failed_jobs:
                    jid = j["id"]
                    jname = j.get("name") or j.get("label") or jid
                    print(f"🚀 Retrying failed job '{jname}' (ID: {jid})...")
                    subprocess.run(["bk", "job", "retry", jid])
            else:
                print(
                    f"🚀 Rebuilding entire build #{build_number} for pipeline: {pipeline}"
                )
                res = subprocess.run(
                    [
                        "bk",
                        "build",
                        "rebuild",
                        build_number,
                        "-p",
                        pipeline,
                        "--yes",
                    ]
                )
                sys.exit(res.returncode)
        except Exception:
            print(
                f"🚀 Rebuilding entire build #{build_number} for pipeline: {pipeline}"
            )
            res = subprocess.run(
                [
                    "bk",
                    "build",
                    "rebuild",
                    build_number,
                    "-p",
                    pipeline,
                    "--yes",
                ]
            )
            sys.exit(res.returncode)


if __name__ == "__main__":
    main()
