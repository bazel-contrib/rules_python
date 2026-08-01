#!/usr/bin/env python3

import argparse
import os
import re
import subprocess
import sys
import urllib.request


def fetch_log(build_id, job_id, output_path):
    if build_id.startswith("http"):
        log_url = build_id
    elif job_id.startswith("http"):
        log_url = job_id
    else:
        log_url = f"https://buildkite.com/organizations/bazel/pipelines/rules-python-python/builds/{build_id}/jobs/{job_id}/download.txt"

    # Check if this is a GitHub Actions job
    gh_match = re.search(r"github\.com/.*/job/(\d+)", log_url) or re.search(
        r"^(\d+)$", job_id
    )
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


def parse_log(log_path):
    if not os.path.exists(log_path):
        return [f"Log file not found at {log_path}"]

    with open(log_path, errors="replace") as f:
        lines = f.readlines()

    errors = []
    for line in lines:
        if any(
            keyword in line
            for keyword in [
                "ERROR:",
                "FAILED:",
                "Critical Path",
                "Traceback",
                "Exception",
                "FileNotFoundError",
                "no such package",
                "no such target",
                "exit code",
                "##[error]",
                "Would reformat:",
                "would be reformatted",
                "error]",
            ]
        ):
            errors.append(line.strip())

    return errors[:30]


def create_plan(job_name, log_path, errors):
    err_str = (
        "\n".join(errors)
        if errors
        else "No obvious keyword error lines matched. Please inspect the raw log file."
    )

    plan = f"""# 🚨 CI Failure Analysis Report: {job_name}

## 📁 CI Log Path
`{log_path}`

## 🔥 Extracted Failure Snippets
```text
{err_str}
```

## 🛠️ Suggested Plan to Fix
1. **Inspect Log**: Review the exact log snippets above or read the full raw log file at `{log_path}`.
2. **Reproduce Locally**: Run `./replicate_ci "{job_name}"` or the matching `bazel build/test` command locally.
3. **Apply Fix**: Resolve the root cause in the relevant `BUILD.bazel` or Starlark files.
4. **Verify & Push**: Run local verification with `--config=fast-tests` and push the updated branch to trigger a clean pipeline.
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

    fetch_log(args.build_id, args.job_id, log_path)

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
