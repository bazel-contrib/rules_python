#!/usr/bin/env python3
"""Merges multiple modules_mapping.json files into a single file."""

import argparse
import json
from pathlib import Path


def simplify(mapping: dict) -> dict:
    """Collapse entries for submodules into entries for their parents
    where possible.  For example, "a.b" and "a.c" become "a".

    This must run over the fully merged mapping; a submodule is redundant only
    when some ancestor resolves to the same wheel, and we can determine that
    only once every wheel has contributed.

    Args:
        mapping: The fully merged module-to-wheel mapping to simplify.
    Returns:
        A new, simplified module-to-wheel mapping.
    """
    simplified = {}
    for module, wheel_name in sorted(mapping.items(), key=lambda x: x[0]):
        mod = module
        while True:
            if mod in simplified:
                if simplified[mod] != wheel_name:
                    break
                wheel_name = ""
                break
            if mod.count(".") == 0:
                break
            mod = mod.rsplit(".", 1)[0]
        if wheel_name:
            simplified[module] = wheel_name
    return simplified


def merge_modules_mappings(input_files: list[Path], output_file: Path) -> None:
    """Merge multiple modules_mapping.json files into one.

    Args:
        input_files: List of paths to input JSON files to merge
        output_file: Path where the merged output should be written
    """
    merged_mapping = {}
    for input_file in input_files:
        mapping = json.loads(input_file.read_text())
        # Merge the mappings, with later files overwriting earlier ones
        # if there are conflicts
        merged_mapping.update(mapping)

    output_file.write_text(json.dumps(simplify(merged_mapping)))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Merge multiple modules_mapping.json files"
    )
    parser.add_argument(
        "--output",
        required=True,
        type=Path,
        help="Output file path for merged mapping",
    )
    parser.add_argument(
        "--inputs",
        required=True,
        nargs="+",
        type=Path,
        help="Input JSON files to merge",
    )

    args = parser.parse_args()
    merge_modules_mappings(args.inputs, args.output)
