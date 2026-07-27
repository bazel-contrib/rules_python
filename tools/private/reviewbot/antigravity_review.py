# /// script
# requires-python = ">=3.11"
# dependencies = [
#     "google-antigravity",
# ]
# ///
import argparse
import asyncio
import subprocess
from pathlib import Path

from google.antigravity import Agent, CapabilitiesConfig, LocalAgentConfig
from google.antigravity.models import GeminiAPIEndpoint, ModelTarget
from google.antigravity.types import BuiltinTools


def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument("--prompt", required=True, help="Path to prompt file")
    parser.add_argument("--diff-file", help="Path to pre-computed diff file")
    return parser.parse_args()


def get_pr_diff(diff_file: str | None = None) -> str:
    """Fetches the git diff for the current pull request against origin/main."""
    if diff_file and Path(diff_file).exists():
        return Path(diff_file).read_text()
    try:
        return subprocess.check_output(
            ["git", "diff", "origin/main...HEAD"], text=True, stderr=subprocess.DEVNULL
        )
    except Exception:
        return "No diff could be automatically extracted via git commands."


async def main():
    args = parse_args()

    # Read prompt file and pre-hydrate with the exact PR code diff
    base_prompt = Path(args.prompt).read_text()
    diff_text = get_pr_diff(args.diff_file)
    prompt = (
        f"{base_prompt}\n\n## Pull Request Git Diff\n"
        f"Here is the exact code diff for this pull request:\n```diff\n{diff_text}\n```"
    )

    # General coordinator instructions for the reviewer agent.
    system_instructions = (
        "You are a code review assistant. Use your available skills to perform "
        "reviews on pull requests."
    )

    # Create the default endpoint picking up GEMINI_API_KEY from the environment.
    endpoint = GeminiAPIEndpoint()

    # Initialize the Antigravity Agent in read-only mode for security.
    # Register the review-pr skill from the local reviewbot folder.
    # Provide a comprehensive prioritized cascade across Gemini 3 models
    # to automatically fall back if any model hits free-tier quota limits (429)
    # or temporary unavailability.
    config = LocalAgentConfig(
        models=[
            ModelTarget(name="gemini-3.5-flash", endpoint=endpoint),
            ModelTarget(name="gemini-3.1-pro-preview", endpoint=endpoint),
            ModelTarget(name="gemini-3.1-flash-lite", endpoint=endpoint),
            ModelTarget(name="gemini-3-pro-preview", endpoint=endpoint),
            ModelTarget(name="gemini-flash-latest", endpoint=endpoint),
            ModelTarget(name="gemini-pro-latest", endpoint=endpoint),
        ],
        system_instructions=system_instructions,
        skills_paths=[str(Path(__file__).parent / "skills" / "review-pr" / "SKILL.md")],
        capabilities=CapabilitiesConfig(
            enabled_tools=BuiltinTools.read_only(),
        ),
    )

    async with Agent(config) as agent:
        response = await agent.chat(prompt)
        report = await response.text()

    print("--- REVIEW REPORT GENERATED ---")
    print(report)

    # TODO: Use GITHUB_TOKEN to post the report back to the PR comments.


if __name__ == "__main__":
    asyncio.run(main())
