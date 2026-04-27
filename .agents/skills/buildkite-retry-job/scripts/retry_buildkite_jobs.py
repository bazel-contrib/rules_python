#!/usr/bin/env python3
import argparse
import json
import os
import sys
import urllib.request
from urllib.error import HTTPError


def make_request(url, method="GET", data=None, token=None):
    headers = {
        "Authorization": f"Bearer {token}",
        "Accept": "application/json",
    }
    if data:
        data = json.dumps(data).encode("utf-8")
        headers["Content-Type"] = "application/json"

    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req) as response:
            return json.loads(response.read().decode())
    except HTTPError as e:
        print(f"HTTP Error: {e.code} - {e.reason}", file=sys.stderr)
        if e.fp:
            print(e.fp.read().decode(), file=sys.stderr)
        return None
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        return None


def main():
    parser = argparse.ArgumentParser(
        description="Retry failed jobs in a Buildkite build."
    )
    parser.add_argument("org", help="Organization slug")
    parser.add_argument("pipeline", help="Pipeline slug")
    parser.add_argument("build", help="Build number")
    parser.add_argument(
        "--job-name",
        help="Specific job name to retry (if failed). Regex/substring allowed.",
    )

    args = parser.parse_args()
    token = os.environ.get("BUILDKITE_API_TOKEN")

    if not token:
        print(
            "Please set the BUILDKITE_API_TOKEN environment variable.", file=sys.stderr
        )
        sys.exit(1)

    url = f"https://api.buildkite.com/v2/organizations/{args.org}/pipelines/{args.pipeline}/builds/{args.build}"
    print(f"Fetching build details from {url}...")
    build_data = make_request(url, token=token)

    if not build_data:
        print("Failed to fetch build details.", file=sys.stderr)
        sys.exit(1)

    jobs = build_data.get("jobs", [])
    failed_jobs = [j for j in jobs if j.get("state") == "failed"]

    if not failed_jobs:
        print("No failed jobs found in this build.")
        sys.exit(0)

    for job in failed_jobs:
        job_id = job.get("id")
        job_name = job.get("name", "Unknown")

        if (
            args.job_name
            and args.job_name.lower() not in job_name.lower()
            and args.job_name.lower() not in job.get("step_key", "").lower()
        ):
            continue

        print(f"Retrying job: {job_name} ({job_id})")
        retry_url = f"https://api.buildkite.com/v2/organizations/{args.org}/pipelines/{args.pipeline}/builds/{args.build}/jobs/{job_id}/retry"

        result = make_request(retry_url, method="PUT", token=token)
        if result:
            print(f"  Successfully triggered retry for {job_name}")
        else:
            print(f"  Failed to trigger retry for {job_name}")


if __name__ == "__main__":
    main()
