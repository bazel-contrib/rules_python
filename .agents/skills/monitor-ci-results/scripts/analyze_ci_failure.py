#!/usr/bin/env python3
# Copyright 2026 The Bazel Authors. All rights reserved.

import argparse
import os
import re
import subprocess


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
                "no such package",
                "no such target",
                "exit code",
            ]
        ):
            errors.append(line.strip())

    return errors[:30]


def create_plan(job_name, log_path, errors):
    err_str = (
        "\n".join(errors)
        if errors
        else "No obvious keyword error lines matched. Please inspect the raw log."
    )

    plan = f"""# 🚨 CI Failure Analysis Report: {job_name}

## 📁 CI Log Path
`{log_path}`

## 🔥 Extracted Failure Snippets
```text
{err_str}
```

## 🛠️ Suggested Plan to Fix
1. **Inspect Log**: Review the exact log snippets above or read the full log file at `{log_path}`.
2. **Reproduce Locally**: Run `./replicate_ci "{job_name}"` or the matching `bazel build/test` command locally.
3. **Apply Fix**: Resolve the underlying Starlark or build setting issue in the relevant `BUILD.bazel` or Starlark files.
4. **Verify & Push**: Run local verification with `--config=fast-tests` and push the updated branch to trigger a clean remote pipeline.
"""
    return plan


def main():
    parser = argparse.ArgumentParser(
        description="Analyze downloaded CI failure log and report back."
    )
    parser.add_argument("job_name", help="Name of the failed job")
    parser.add_argument("log_path", help="Path to the downloaded log file")
    parser.add_argument("conv_id", help="Conversation ID to report back to")
    args = parser.parse_args()

    print(f"🚀 Analyzing CI failure log for '{args.job_name}' at '{args.log_path}'...")
    errors = parse_log(args.log_path)
    plan = create_plan(args.job_name, args.log_path, errors)

    plan_file = os.path.join(
        os.path.dirname(args.log_path),
        f"ci_plan_{re.sub(r'[^a-zA-Z0-9]', '_', args.job_name)}.md",
    )
    with open(plan_file, "w") as f:
        f.write(plan)

    print(
        f"📄 Plan generated at '{plan_file}'. Sending notification to conversation {args.conv_id}..."
    )

    msg = f"⚠️ Remote CI Job '{args.job_name}' completed with errors!\n\nI executed a background failure analysis task. My findings and suggested fix plan have been compiled at artifact file: `{plan_file}`.\n\nDownloaded CI Log File: `{args.log_path}`"

    res = subprocess.run(
        [
            "agentapi",
            "send-message",
            "--title=CI Job Failure Plan",
            args.conv_id,
            msg,
        ]
    )
    if res.returncode != 0:
        print(f"❌ Failed to send agentapi message. Printing plan directly:\n{plan}")


if __name__ == "__main__":
    main()
