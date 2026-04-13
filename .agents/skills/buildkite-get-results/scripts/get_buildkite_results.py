#!/usr/bin/env python3
import argparse
import json
import re
import subprocess
import sys
import urllib.request


def get_pr_checks(pr_number):
    try:
        # Check if gh is installed
        subprocess.run(
            ["gh", "--version"],
            check=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
    except FileNotFoundError:
        print(
            "Error: 'gh' (GitHub CLI) is not installed or not in PATH.", file=sys.stderr
        )
        sys.exit(1)
    except subprocess.CalledProcessError:
        print("Error: 'gh' command failed. Is it installed?", file=sys.stderr)
        sys.exit(1)

    cmd = ["gh", "pr", "checks", str(pr_number), "--json", "bucket,name,link,state"]
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, check=True)
        return json.loads(result.stdout)
    except subprocess.CalledProcessError as e:
        print(f"Error fetching PR checks: {e.stderr}", file=sys.stderr)
        sys.exit(1)


def get_buildkite_build_url(checks):
    for check in checks:
        # Looking for Buildkite check. The name usually contains "buildkite"
        if "buildkite" in check.get("name", "").lower():
            return check.get("link")
    return None


def fetch_buildkite_data(build_url):
    # Convert https://buildkite.com/org/pipeline/builds/number
    # to https://buildkite.com/org/pipeline/builds/number.json
    if not build_url.endswith(".json"):
        json_url = build_url + ".json"
    else:
        json_url = build_url

    try:
        with urllib.request.urlopen(json_url) as response:
            if response.status != 200:
                print(
                    f"Error fetching data from {json_url}: Status {response.status}",
                    file=sys.stderr,
                )
                return None
            return json.loads(response.read().decode())
    except Exception as e:
        print(f"Error fetching data from {json_url}: {e}", file=sys.stderr)
        return None


def download_log(job_url, output_path):
    # Construct raw log URL: job_url + "/raw" (Buildkite convention)
    # job_url e.g. https://buildkite.com/org/pipeline/builds/14394#job-id
    # Wait, the job['path'] gives /org/pipeline/builds/14394#job-id
    # We want /org/pipeline/builds/14394/jobs/job-id/raw? No
    # The clean URL for a job is https://buildkite.com/org/pipeline/builds/14394/jobs/job-id
    # And raw log is https://buildkite.com/org/pipeline/builds/14394/jobs/job-id/raw

    # We have full_url e.g. https://buildkite.com/bazel/rules-python-python/builds/14394#019c5cf9-e3cf-468f-a7b1-8f9f5ad4b08c
    # We need to transform it.

    if "#" in job_url:
        base, job_id = job_url.split("#")
        # Ensure base doesn't end with /
        if base.endswith("/"):
            base = base[:-1]

        # Build raw URL
        raw_url = f"{base}/jobs/{job_id}/raw"
    else:
        print(f"Could not parse job URL for download: {job_url}", file=sys.stderr)
        return False

    try:
        with urllib.request.urlopen(raw_url) as response:
            if response.status != 200:
                print(
                    f"Error downloading log from {raw_url}: Status {response.status}",
                    file=sys.stderr,
                )
                return False
            with open(output_path, "wb") as f:
                f.write(response.read())
        return True
    except Exception as e:
        print(f"Error downloading log from {raw_url}: {e}", file=sys.stderr)
        return False


def main():
    parser = argparse.ArgumentParser(description="Get Buildkite CI results for a PR.")
    parser.add_argument("pr_number", help="The PR number.")
    parser.add_argument(
        "--jobs",
        action="append",
        help="Filter by job name (regex match). Can be specified multiple times.",
    )
    parser.add_argument(
        "--download",
        action="store_true",
        help="If exactly one job is matched, download its log to a local file.",
    )

    args = parser.parse_args()

    print(f"Fetching checks for PR #{args.pr_number}...", file=sys.stderr)
    checks = get_pr_checks(args.pr_number)

    build_url = get_buildkite_build_url(checks)
    if not build_url:
        print("No Buildkite check found for this PR.", file=sys.stderr)
        sys.exit(1)

    print(f"Found Buildkite URL: {build_url}", file=sys.stderr)

    data = fetch_buildkite_data(build_url)
    if not data:
        sys.exit(1)

    print(f"Build State: {data.get('state')}")
    print("-" * 40)

    jobs = data.get("jobs", [])

    filtered_jobs = []
    if args.jobs:
        for job in jobs:
            job_name = job.get("name")
            if not job_name:
                continue
            for pattern in args.jobs:
                if re.search(pattern, job_name, re.IGNORECASE):
                    filtered_jobs.append(job)
                    break
    else:
        filtered_jobs = jobs

    for job in filtered_jobs:
        name = job.get("name", "Unknown")
        state = job.get("state", "Unknown")
        path = job.get("path")
        full_url = f"https://buildkite.com{path}" if path else "N/A"

        passed = job.get("passed", False)
        outcome = job.get("outcome")

        if passed:
            result_str = "PASSED"
        elif outcome:
            result_str = outcome.upper()
        else:
            result_str = state.upper()

        print(f"Job: {name}")
        print(f"  Result: {result_str}")
        print(f"  URL: {full_url}")
        print("")

    if args.download:
        if len(filtered_jobs) == 1:
            job = filtered_jobs[0]
            name = job.get("name", "unknown_job")
            # Sanitize name for filename
            safe_name = re.sub(r"[^a-zA-Z0-9_\-]", "_", name)
            output_path = f"{safe_name}.log"

            path = job.get("path")
            if path:
                full_url = f"https://buildkite.com{path}"
                print(f"Downloading log for '{name}'...", file=sys.stderr)
                if download_log(full_url, output_path):
                    print(f"Downloaded log to: {output_path}")
                else:
                    print("Failed to download log.", file=sys.stderr)
            else:
                print("Job has no URL path, cannot download.", file=sys.stderr)
        elif len(filtered_jobs) == 0:
            print("No jobs matched to download.", file=sys.stderr)
        else:
            print(
                f"Matched {len(filtered_jobs)} jobs. Please filter to exactly one job to download.",
                file=sys.stderr,
            )


if __name__ == "__main__":
    main()
