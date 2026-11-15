#!/usr/bin/env python3

import argparse
import os
import re
import subprocess
import sys
import urllib.parse
import urllib.request

_ANSI_ESCAPE = re.compile(
    r"\x1B(?:[_\]][^\x07\x1B]*(?:\x07|\x1B\\)|[@-Z\\-_]|\[[0-?]*[ -/]*[@-~])"
)
_BUILDKITE_TIMESTAMP = re.compile(r"^_?bk;t=\d+\s*")
_HTTP_5XX_DOWNLOAD_ERROR = re.compile(r"get returned 5\d\d\b", re.IGNORECASE)

_HTTP_GATEWAY_ERRORS = (
    # keep-sorted start
    "502 bad gateway",
    "503 service unavailable",
    "504 gateway time-out",
    # keep-sorted end
)

_DNS_OR_GIT_MIRROR_ERRORS = (
    # keep-sorted start
    "could not resolve host:",
    "getting/updating git mirror:",
    "temporary failure in name resolution",
    # keep-sorted end
)

_MODEXTWD_CLEANUP_ERRORS = (
    # keep-sorted start
    "failed to clean up module context directory:",
    # keep-sorted end
)

_ERROR_KEYWORDS = (
    _HTTP_GATEWAY_ERRORS
    + _DNS_OR_GIT_MIRROR_ERRORS
    + _MODEXTWD_CLEANUP_ERRORS
    + (
        # keep-sorted start
        "##[error]",
        "connection reset by peer",
        "critical path",
        "curl: (",
        "errno 5",
        "error downloading [",
        "error during connect:",
        "error waiting for container",
        "error:",
        "error]",
        "exception",
        "exit code",
        "exit-code",
        "failed:",
        "fatal",
        "fatal:",
        "filenotfounderror",
        "get returned 5",
        "input/output error",
        "no such package",
        "no such target",
        "status 125",
        "traceback",
        "unable to find bazelisk version",
        "user command error:",
        "would be reformatted",
        "would reformat:",
        # keep-sorted end
    )
)


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
    gh_repo_match = re.search(
        r"github\.com/([^/]+/[^/]+)/actions/runs/\d+/job/(\d+)", log_url
    )
    gh_match = gh_repo_match or re.search(r"github\.com/.*/job/(\d+)", log_url)
    if not gh_match and "github" in job_name.lower() and re.match(r"^\d+$", job_id):
        gh_match = re.match(r"^(\d+)$", job_id)

    if gh_match:
        if gh_repo_match:
            gh_repo = gh_repo_match.group(1)
            gh_job_id = gh_repo_match.group(2)
        else:
            gh_repo = "bazel-contrib/rules_python"
            gh_job_id = gh_match.group(1)
        print(f"📥 Fetching GitHub Action log for job {gh_job_id} using gh CLI...")
        api_cmd = [
            "gh",
            "api",
            # Raw job logs contain ANSI color codes that gh api rejects by
            # default; parse_log() strips them.
            "--allow-escape-sequences",
            f"repos/{gh_repo}/actions/jobs/{gh_job_id}/logs",
        ]
        try:
            res = subprocess.run(api_cmd, capture_output=True, text=True, check=True)
            if res.stdout.strip():
                with open(output_path, "w") as f:
                    f.write(res.stdout)
                return True
        except Exception as e:
            print(
                f"⚠️ Failed to fetch GitHub log via gh api for job {gh_job_id}: {e}",
                file=sys.stderr,
            )

        cmd = ["gh", "run", "view", "--job", gh_job_id, "--repo", gh_repo, "--log"]
        try:
            res = subprocess.run(cmd, capture_output=True, text=True, check=True)
            if (
                res.stdout.strip()
                and "is still in progress; logs will be available when it is complete"
                not in res.stdout
            ):
                with open(output_path, "w") as f:
                    f.write(res.stdout)
                return True
        except Exception as e:
            print(
                f"⚠️ Failed to fetch GitHub log via gh CLI for job {gh_job_id}: {e}",
                file=sys.stderr,
            )

    parsed_url = urllib.parse.urlsplit(log_url)
    if not log_url.endswith("/download.txt") and parsed_url.netloc in (
        "buildkite.com",
        "www.buildkite.com",
    ):
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


def _contains_any(lines, substrings):
    for line in lines:
        lower_line = line.lower()
        if any(sub in lower_line for sub in substrings):
            return True
    return False


def _is_repo_download_flake(errors):
    """Returns whether error lines indicate a transient Bazel download failure.

    Args:
        errors: Sequence of extracted error log lines.

    Returns:
        True if any line shows an HTTP 5xx or transient download failure.
    """
    for err in errors:
        if _HTTP_5XX_DOWNLOAD_ERROR.search(err):
            return True
        lower_err = err.lower()
        if "error downloading [" in lower_err and any(
            reason in lower_err
            for reason in (
                "timed out",
                "connection reset",
                "unexpected end of file",
            )
        ):
            return True
    return False


def parse_log(log_path):
    if not os.path.exists(log_path):
        return [f"Log file not found at {log_path}"]

    with open(log_path, errors="replace") as f:
        lines = f.readlines()

    errors = []
    for line in lines:
        clean_line = _ANSI_ESCAPE.sub("", line).strip()
        # Strip pre-stripped `_bk;t=` / `bk;t=` prefixes in addition to APC sequences.
        clean_line = _BUILDKITE_TIMESTAMP.sub("", clean_line)
        lower_line = clean_line.lower()
        if clean_line and any(kw in lower_line for kw in _ERROR_KEYWORDS):
            errors.append(clean_line)

    return errors[:30]


def create_plan(job_name, log_path, errors):
    err_str = (
        "\n".join(errors)
        if errors
        else "No obvious keyword error lines matched. Please inspect the raw log file."
    )

    lower_job_name = job_name.lower()
    is_docs_job = "docs" in lower_job_name or "readthedocs" in lower_job_name
    has_exit_code_2 = _contains_any(errors, ("exit code 2", "exit-code: 2"))

    is_flake = False
    flake_reason = ""
    if any(
        "fatal: destination path '.' already exists and is not an empty directory." in e
        for e in errors
    ):
        is_flake = True
        flake_reason = "ReadTheDocs workspace checkout race / dirty container environment where target directory is not empty (`fatal: destination path '.' already exists`). This is an infrastructure flake, not a codebase failure."
    elif is_docs_job and has_exit_code_2:
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
    elif _is_repo_download_flake(errors):
        is_flake = True
        flake_reason = (
            "Transient Bazel repository download failure (HTTP 5xx or I/O error). "
            "Check if the archive is available on mirror.bazel.build before retrying."
        )
    elif _contains_any(errors, _HTTP_GATEWAY_ERRORS):
        is_flake = True
        flake_reason = (
            "Upstream HTTP 502/503/504 gateway timeout during download "
            "(infrastructure flake)."
        )
    elif any(
        "curl:" in e.lower()
        or "recv failure: connection reset" in e.lower()
        or "connection reset by peer" in e.lower()
        for e in errors
    ):
        is_flake = True
        flake_reason = "Network connection reset during runner bootstrap or artifact download (curl recv failure / connection reset). This is an infrastructure network flake."
    elif any(
        "input/output error" in e.lower() or "errno 5" in e.lower() for e in errors
    ):
        is_flake = True
        flake_reason = "Transient runner host disk / Darwin sandbox I/O error (OSError: [Errno 5] Input/output error). This is an infrastructure flake, not a codebase defect."
    elif any("unable to find bazelisk version" in e.lower() for e in errors):
        is_flake = True
        flake_reason = (
            "Transient network error fetching Bazelisk release metadata during "
            "GitHub Actions `setup-bazel` step (`Unable to find Bazelisk version`). "
            "This is an infrastructure network flake, not a codebase bug."
        )
    elif _contains_any(errors, _DNS_OR_GIT_MIRROR_ERRORS):
        is_flake = True
        flake_reason = (
            "Transient CI runner DNS resolution or git mirror checkout failure. "
            "This is an infrastructure network flake, not a codebase bug."
        )
    elif _contains_any(errors, _MODEXTWD_CLEANUP_ERRORS):
        is_flake = True
        flake_reason = (
            "Transient Windows file-lock race while Bazel cleaned up a temporary "
            "`modextwd` module extension directory (`Permission denied`). "
            "This is an infrastructure flake, not a codebase bug."
        )

    classification = (
        "⚡ **Classification**: **Infrastructure / Flake Issue** (Not a codebase bug)"
        if is_flake
        else "🔍 **Classification**: **Code / Configuration Issue**"
    )
    fix_advice = (
        f"Retry the failed job (`retry-ci-job`). {flake_reason}"
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
    safe_jid = re.sub(r"[^a-zA-Z0-9_-]", "_", args.job_id)
    log_path = os.path.join(scratch_dir, f"ci_{safe_jname}_{safe_jid}.log")

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
