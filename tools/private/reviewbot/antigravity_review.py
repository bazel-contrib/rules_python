import argparse
import asyncio
from pathlib import Path

from google.antigravity import Agent, CapabilitiesConfig, LocalAgentConfig


def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument("--prompt", required=True, help="Path to prompt file")
    return parser.parse_args()


async def main():
    args = parse_args()

    # Read prompt file
    prompt = Path(args.prompt).read_text()

    # Initialize the Antigravity Agent in read-only mode for security.
    # Register the review-pr skill from the local reviewbot folder.
    config = LocalAgentConfig(
        skills_paths=["tools/private/reviewbot/skills/review-pr"],
        capabilities=CapabilitiesConfig(
            allow_filesystem_read=True,
            allow_filesystem_write=False,
            allow_network=False,
        ),
    )

    # General coordinator instructions for the reviewer agent.
    system_instructions = (
        "You are a code review assistant. Use your available skills to perform "
        "reviews on pull requests."
    )

    async with Agent(config, system_instructions=system_instructions) as agent:
        response = await agent.chat(prompt)
        report = await response.text()

    print("--- REVIEW REPORT GENERATED ---")
    print(report)

    # TODO: Use GITHUB_TOKEN to post the report back to the PR comments.


if __name__ == "__main__":
    asyncio.run(main())
