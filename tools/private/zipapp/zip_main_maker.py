"""Creates the __main__.py for a zipapp by populating a template.

This program also calculates a hash of the application files to include in
the template, which allows making the extraction directory unique to the
content of the zipapp.
"""

import argparse
import hashlib
import os

BLOCK_SIZE = 256 * 1024


def create_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(fromfile_prefix_chars="@")
    parser.add_argument("--template", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--substitution", action="append", default=[])
    parser.add_argument(
        "--hash_files_manifest",
        required=True,
        help="A file containing lines in rf-XXX formats (rf-empty, rf-file, rf-symlink, etc.)",
    )
    return parser


def compute_inputs_hash(manifest_path: str) -> str:
    h = hashlib.sha256()
    with open(manifest_path, "r", encoding="utf-8") as f:
        manifest_lines = f.read().splitlines()

    # Sort lines for determinism. Hash the paths (to capture structure) and the
    # content.
    for line in sorted(manifest_lines):
        type_, _, rest = line.partition("|")
        h.update(rest.encode("utf-8"))
        parts = rest.split("|")

        if type_ == "rf-empty":
            continue

        is_symlink_str = parts[0]
        path = parts[-1]

        if is_symlink_str == "-1":
            is_symlink = not os.path.exists(path)
        else:
            is_symlink = is_symlink_str == "1"

        if is_symlink:
            h.update(os.readlink(path).encode("utf-8"))
        else:
            with open(path, "rb") as f:
                while True:
                    chunk = f.read(BLOCK_SIZE)
                    if not chunk:
                        break
                    h.update(chunk)

    return h.hexdigest()


def expand_template(template_path: str, output_path: str, substitutions: dict) -> None:
    with open(template_path, "r", encoding="utf-8") as f:
        content = f.read()

    for key, val in substitutions.items():
        content = content.replace(key, val)

    with open(output_path, "w", encoding="utf-8") as f:
        f.write(content)


def main():
    parser = create_parser()
    args = parser.parse_args()

    app_hash = compute_inputs_hash(args.hash_files_manifest)

    substitutions = {"%APP_HASH%": app_hash}
    for s in args.substitution:
        key, val = s.split("=", 1)
        substitutions[key] = val

    expand_template(args.template, args.output, substitutions)


if __name__ == "__main__":
    main()
