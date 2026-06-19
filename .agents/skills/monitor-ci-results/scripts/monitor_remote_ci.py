#!/usr/bin/env python3

import argparse
import json
import os
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

                passed = 0
                failed = 0
                running = 0
                other = 0

                for job in jobs:
                    jstate = job.get("state", "unknown")
                    exit_status = job.get("exit_status")
                    is_soft_failed = job.get("soft_failed") is True
                    is_failed = (
                        jstate in ["failed", "failing"]
                        or (exit_status != 0 and exit_status is not None)
                    ) and not is_soft_failed
                    is_passed = (
                        jstate in ["passed", "success"]
                        or (jstate == "finished" and exit_status == 0)
                        or is_soft_failed
                    )
                    is_running = jstate in ["running", "scheduled"]

                    if is_failed:
                        failed += 1
                    elif is_passed:
                        passed += 1
                    elif is_running:
                        running += 1
                    else:
                        other += 1

                build_id = link.split("/")[-1].split("#")[0]
                print(
                    f"Buildkite #{build_id}: {len(jobs)} total jobs "
                    f"(Passed: {passed}, Failed: {failed}, Running: {running}, Other: {other})"
                )

                for job in jobs:
                    jname = job.get("name", "unknown_job")
                    jstate = job.get("state", "unknown")
                    jid = job.get("id", "")
                    jkey = f"bk_{jid}"

                    exit_status = job.get("exit_status")
                    is_soft_failed = job.get("soft_failed") is True
                    is_failed = (
                        jstate in ["failed", "failing"]
                        or (exit_status != 0 and exit_status is not None)
                    ) and not is_soft_failed

                    if is_failed and jkey not in monitored:
                        print(
                            f"🚨 Notifying failure for Buildkite job '{jname}' (ID: {jid})..."
                        )
                        msg = (
                            f"⚠️ Remote CI Buildkite Job '{jname}' completed with errors!\n\n"
                            f"Build ID: {build_id} | Job ID: {jid}\n"
                            f"Log URL: {job.get('log_url', link)}\n\n"
                            f"Start subagent: run analyze-ci-failure skill on this failure"
                        )
                        subprocess.run(
                            [
                                "agentapi",
                                "send-message",
                                "--title=CI Job Failed",
                                args.conv_id,
                                msg,
                            ]
                        )
                        monitored[jkey] = time.time()
                        with open(state_file, "w") as f:
                            json.dump(monitored, f)

            elif state in ["FAILURE", "failed"] and name not in monitored:
                print(f"🚨 Notifying failure for GitHub check '{name}'...")
                msg = (
                    f"⚠️ Remote CI GitHub Check '{name}' completed with errors!\n\n"
                    f"Link: {link}\n\n"
                    f"Start subagent: run analyze-ci-failure skill on this failure"
                )
                subprocess.run(
                    [
                        "agentapi",
                        "send-message",
                        "--title=CI Check Failed",
                        args.conv_id,
                        msg,
                    ]
                )
                monitored[name] = time.time()
                with open(state_file, "w") as f:
                    json.dump(monitored, f)

        time.sleep(args.interval)

    print("🏁 CI monitoring service completed its scheduled iterations.")


if __name__ == "__main__":
    main()
