#!/usr/bin/env python3
# Copyright 2026 The Bazel Authors. All rights reserved.

import argparse
import json
import os
import re
import subprocess
import sys
import time
import urllib.request


def check_cli(cmd_name):
    try:
        subprocess.run(
            [cmd_name, "--version"],
            check=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        return True
    except Exception:
        return False


def get_pr_checks(pr_number):
    if not check_cli("gh"):
        print("❌ 'gh' CLI not installed.", file=sys.stderr)
        return []
    cmd = ["gh", "pr", "checks", str(pr_number), "--json", "name,link,state"]
    try:
        res = subprocess.run(cmd, capture_output=True, text=True)
        out = res.stdout
        json_str = out[out.find("[") : out.rfind("]") + 1] if "[" in out else "[]"
        return json.loads(json_str)
    except Exception as e:
        print(f"⚠️ Error fetching PR checks: {e}", file=sys.stderr)
        return []


def get_buildkite_jobs(build_url):
    base_url = build_url.split("#")[0]
    if base_url.endswith(".json"):
        base_url = base_url[:-5]

    jobs_url = f"{base_url}/data/jobs.json"
    req = urllib.request.Request(jobs_url, headers={"User-Agent": "ci-monitor"})
    try:
        with urllib.request.urlopen(req) as resp:
            data = json.loads(resp.read().decode())
            if isinstance(data, list):
                return data
            elif isinstance(data, dict) and "records" in data:
                return data["records"]
    except Exception as e:
        print(
            f"⚠️ Could not fetch Buildkite jobs from {jobs_url}: {e}",
            file=sys.stderr,
        )
    return []


def download_buildkite_log(job, output_path):
    log_url = job.get("log_url")
    if not log_url:
        jid = job.get("id")
        log_url = f"https://buildkite.com/organizations/bazel/pipelines/rules-python-python/builds/15716/jobs/{jid}/download.txt"

    if not log_url.endswith("/download.txt") and "buildkite.com" in log_url:
        log_url = re.sub(r"/log$", "/download.txt", log_url)

    req = urllib.request.Request(log_url, headers={"User-Agent": "ci-monitor"})
    try:
        with urllib.request.urlopen(req) as resp:
            content = resp.read()
            with open(output_path, "wb") as f:
                f.write(content)
        return True
    except Exception as e:
        print(f"⚠️ Failed to download log from {log_url}: {e}", file=sys.stderr)
        with open(output_path, "w") as f:
            f.write(
                f"Failed to download log from {log_url}: {e}\nRaw job metadata:\n{json.dumps(job, indent=2)}"
            )
        return False


def main():
    parser = argparse.ArgumentParser(
        description="Monitor remote CI for failures and trigger analysis."
    )
    parser.add_argument("pr", help="PR number to monitor")
    parser.add_argument("conv_id", help="Conversation ID to report back to")
    parser.add_argument(
        "--interval",
        type=int,
        default=60,
        help="Monitoring polling interval in seconds",
    )
    parser.add_argument(
        "--max-iterations",
        type=int,
        default=120,
        help="Maximum number of polling cycles",
    )
    args = parser.parse_args()

    skill_dir = os.path.abspath(os.path.dirname(__file__))
    logs_dir = os.path.join(skill_dir, "ci_logs")
    os.makedirs(logs_dir, exist_ok=True)

    state_file = os.path.join(skill_dir, f"monitored_state_pr_{args.pr}.json")
    monitored = {}
    if os.path.exists(state_file):
        try:
            with open(state_file) as f:
                monitored = json.load(f)
        except Exception:
            pass

    print(
        f"🚀 Starting continuous remote CI monitoring for PR #{args.pr} every {args.interval}s..."
    )
    analyzer_script = os.path.join(skill_dir, "analyze_ci_failure.py")

    for i in range(args.max_iterations):
        print(
            f"🔍 [Cycle {i + 1}/{args.max_iterations}] Polling GitHub PR #{args.pr} checks..."
        )
        checks = get_pr_checks(args.pr)

        for check in checks:
            name = check.get("name", "unknown")
            state = check.get("state", "UNKNOWN")
            link = check.get("link", "")

            if "buildkite" in name.lower() and link:
                jobs = get_buildkite_jobs(link)
                for job in jobs:
                    jname = job.get("name", "unknown_job")
                    jstate = job.get("state", "unknown")
                    jid = job.get("id", "")
                    jkey = f"bk_{jid}"

                    exit_status = job.get("exit_status")
                    is_failed = jstate in ["failed", "failing"] or (
                        exit_status != 0 and exit_status is not None
                    )

                    if is_failed and jkey not in monitored:
                        print(
                            f"🚨 New Buildkite job error detected: '{jname}' (ID: {jid})"
                        )
                        log_path = os.path.join(
                            logs_dir,
                            f"bk_{re.sub(r'[^a-zA-Z0-9]', '_', jname)}_{jid}.log",
                        )
                        download_buildkite_log(job, log_path)

                        print(f"🚀 Starting background analysis task for '{jname}'...")
                        subprocess.Popen(
                            [
                                sys.executable,
                                analyzer_script,
                                jname,
                                log_path,
                                args.conv_id,
                            ]
                        )

                        monitored[jkey] = time.time()
                        with open(state_file, "w") as f:
                            json.dump(monitored, f)

            elif state in ["FAILURE", "failed"] and name not in monitored:
                print(f"🚨 New GitHub check error detected: '{name}'")
                log_path = os.path.join(
                    logs_dir, f"gh_{re.sub(r'[^a-zA-Z0-9]', '_', name)}.log"
                )
                with open(log_path, "w") as f:
                    f.write(
                        f"GitHub Check '{name}' failed.\nLink: {link}\nState: {state}\n"
                    )

                print(f"🚀 Starting background analysis task for '{name}'...")
                subprocess.Popen(
                    [
                        sys.executable,
                        analyzer_script,
                        name,
                        log_path,
                        args.conv_id,
                    ]
                )

                monitored[name] = time.time()
                with open(state_file, "w") as f:
                    json.dump(monitored, f)

        time.sleep(args.interval)

    print("🏁 CI monitoring service completed its scheduled iterations.")


if __name__ == "__main__":
    main()
