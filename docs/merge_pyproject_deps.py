import argparse
import re
from pathlib import Path

import tomllib


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Merge dependencies from additional pyproject.toml files into a main pyproject.toml.",
    )
    parser.add_argument(
        "srcs",
        nargs="+",
        type=Path,
        help="Input pyproject.toml files, with the first being the main file.",
    )
    parser.add_argument(
        "--output",
        required=True,
        type=Path,
        help="Path to output merged pyproject.toml",
    )
    args = parser.parse_args()

    main_path = args.srcs[0]
    additional_paths = args.srcs[1:]

    main_text = main_path.read_text(encoding="utf-8")
    extra_dependencies = []
    for path in additional_paths:
        data = tomllib.loads(path.read_text(encoding="utf-8"))
        extra_dependencies.extend(data.get("project", {}).get("dependencies", []))

    lines = "\n".join(f'    "{d}",' for d in sorted(set(extra_dependencies))) + "\n"
    # tomllib is read-only. Regex substitution avoids needing 3rd-party TOML
    # writing libraries while preserving existing formatting and comments.
    new_text = re.sub(
        r"(\bdependencies\s*=\s*\[)",
        r"\1\n" + lines.replace("\\", "\\\\"),
        main_text,
        count=1,
    )
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(new_text, encoding="utf-8")


if __name__ == "__main__":
    main()
