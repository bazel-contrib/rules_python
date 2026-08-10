#!/usr/bin/env python3

import argparse
import os
import re
import subprocess
import sys
import urllib.request


def fetch_log(job_name, build_id, job_id, output_path):
    if (
        "readthedocs" in job_name.lower()
        or "readthedocs" in build_id.lower()
        or "readthedocs" in job_id.lower()
    ):
        rtd_match = re.search(r"(\d+)", build_id) or re.search(r"(\d+)", job_id)
        if rtd_match:
            rtd_id = rtd_match.group(1)
            rtd_url = f"https://app.readthedocs.org/api/v2/build/{rtd_id}.txt"
            print(f"📥 Downloading ReadTheDocs failure log from {rtd_url}...")
            req = urllib.request.Request(rtd_url, headers={"User-Agent": "ci-analyzer"})
            try:
                with urllib.request.urlopen(req) as resp:
                    content = resp.read()
                    with open(output_path, "wb") as f:
                        f.write(content)
                return True
            except Exception as e:
                print(
                    f"⚠️ Failed to download RTD log from {rtd_url}: {e}", file=sys.stderr
                )

    if build_id.startswith("http"):
        log_url = build_id
    elif job_id.startswith("http"):
        log_url = job_id
    else:
        log_url = f"https://buildkite.com/organizations/bazel/pipelines/rules-python-python/builds/{build_id}/jobs/{job_id}/download.txt"

    # Check if this is a GitHub Actions job
    gh_match = re.search(r"github\.com/.*/job/(\d+)", log_url)
    if not gh_match and "github" in job_name.lower() and re.match(r"^\d+$", job_id):
        gh_match = re.match(r"^(\d+)$", job_id)

    if gh_match:
        gh_job_id = gh_match.group(1)
        print(f"📥 Fetching GitHub Action log for job {gh_job_id} using gh CLI...")
        cmd = ["gh", "run", "view", "--job", gh_job_id, "--log"]
        try:
            res = subprocess.run(cmd, capture_output=True, text=True, check=True)
            with open(output_path, "w") as f:
                f.write(res.stdout)
            return True
        except Exception as e:
            print(
                f"⚠️ Failed to fetch GitHub log via gh CLI for job {gh_job_id}: {e}",
                file=sys.stderr,
            )

    if not log_url.endswith("/download.txt") and "buildkite.com" in log_url:
        log_url = re.sub(r"/log$", "/download.txt", log_url)

    print(f"📥 Downloading CI failure log from {log_url}...")
    req = urllib.request.Request(log_url, headers={"User-Agent": "ci-analyzer"})
    try:
        with urllib.request.urlopen(req) as resp:
            content = resp.read()
            with open(output_path, "wb") as f:
                f.write(content)
        return True
    except Exception as e:
        print(f"⚠️ Failed to download log from {log_url}: {e}", file=sys.stderr)
        with open(output_path, "w") as f:
            f.write(f"Failed to download log from {log_url}: {e}\n")
        return False


ANSI_ESCAPE = re.compile(r"\x1B(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~])")


def parse_log(log_path):
    if not os.path.exists(log_path):
        return [f"Log file not found at {log_path}"]

    with open(log_path, errors="replace") as f:
        lines = f.readlines()

    errors = []
    for line in lines:
        clean_line = ANSI_ESCAPE.sub("", line).strip()
        # Clean buildkite timestamp prefix: _bk;t=...
        clean_line = re.sub(r"^_bk;t=\d+\s*", "", clean_line)
        if any(
            keyword.lower() in clean_line.lower()
            for keyword in [
                "error:",
                "failed:",
                "critical path",
                "traceback",
                "exception",
                "filenotfounderror",
                "no such package",
                "no such target",
                "exit code",
                "exit-code",
                "status 125",
                "fatal:",
                "fatal",
                "##[error]",
                "would reformat:",
                "would be reformatted",
                "error]",
                "error waiting for container",
                "error during connect:",
                "user command error:",
            ]
        ):
            if clean_line:
                errors.append(clean_line)

    return errors[:30]


def create_plan(job_name, log_path, errors):
    err_str = (
        "\n".join(errors)
        if errors
        else "No obvious keyword error lines matched. Please inspect the raw log file."
    )

    is_flake = False
    flake_reason = ""
    if any(
        "fatal: destination path '.' already exists and is not an empty directory." in e
        for e in errors
    ):
        is_flake = True
        flake_reason = "ReadTheDocs workspace checkout race / dirty container environment where target directory is not empty (`fatal: destination path '.' already exists`). This is an infrastructure flake, not a codebase failure."
    elif any("exit code 2" in e.lower() for e in errors) and (
        "docs" in job_name.lower() or "readthedocs" in job_name.lower()
    ):
        is_flake = True
        flake_reason = "Known docs build flake with exit code 2."
    elif any(
        "error waiting for container" in e.lower()
        or "status 125" in e.lower()
        or "error during connect:" in e.lower()
        or "docker-buildkite-plugin command hook exited with status 125" in e.lower()
        for e in errors
    ):
        is_flake = True
        flake_reason = "Buildkite agent / Docker runner infrastructure failure (dockerd disconnection / grpc context canceled / exit status 125). This is an infrastructure flake, not a codebase bug."

    classification = (
        "⚡ **Classification**: **Infrastructure / Flake Issue** (Not a codebase bug)"
        if is_flake
        else "🔍 **Classification**: **Code / Configuration Issue**"
    )
    fix_advice = (
        f"Retry the failed job (`buildkite-retry-job`). {flake_reason}"
        if is_flake
        else "Resolve the root cause in the relevant source / build files."
    )

    plan = f"""# 🚨 CI Failure Analysis Report: {job_name}

{classification}

## 📁 CI Log Path
`{log_path}`

## 🔥 Extracted Failure Snippets
```text
{err_str}
```

## 🛠️ Suggested Plan to Fix
1. **Diagnosis**: {flake_reason if is_flake else "Review extracted errors."}
2. **Action**: {fix_advice}
3. **Verify**: Check the new build status once re-triggered.
"""
    return plan


def main():
    parser = argparse.ArgumentParser(
        description="Download CI failure log, analyze root cause, and create fix plan."
    )
    parser.add_argument("job_name", help="Name of the failed job")
    parser.add_argument("build_id", help="Buildkite Build ID, Build number, or Log URL")
    parser.add_argument("job_id", help="Buildkite Job ID or link")
    parser.add_argument("conv_id", help="Conversation ID to report back to")
    args = parser.parse_args()

    skill_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
    scratch_dir = os.path.join(skill_dir, "scratch")
    os.makedirs(scratch_dir, exist_ok=True)

    safe_jname = re.sub(r"[^a-zA-Z0-9]", "_", args.job_name)
    log_path = os.path.join(scratch_dir, f"ci_{safe_jname}_{args.job_id}.log")

    fetch_log(args.job_name, args.build_id, args.job_id, log_path)

    print(f"🚀 Analyzing CI failure log for '{args.job_name}' at '{log_path}'...")
    errors = parse_log(log_path)
    plan = create_plan(args.job_name, log_path, errors)

    plan_file = os.path.join(scratch_dir, f"ci_plan_{safe_jname}.md")
    with open(plan_file, "w") as f:
        f.write(plan)

    print(
        f"📄 Plan generated at '{plan_file}'. Dispatching notification to conversation {args.conv_id}..."
    )

    msg = (
        f"⚠️ Remote CI Job '{args.job_name}' Analysis Complete!\n\n"
        f"I downloaded and analyzed the failure log. Findings and suggested fix plan compiled at artifact file: `{plan_file}`.\n\n"
        f"Raw CI Log Path: `{log_path}`"
    )

    res = subprocess.run(
        [
            "agentapi",
            "send-message",
            "--title=CI Failure Analysis Plan",
            args.conv_id,
            msg,
        ]
    )
    if res.returncode != 0:
        print(f"❌ Failed to send agentapi message. Printing plan directly:\n{plan}")


if __name__ == "__main__":
    main()
