import argparse
from pathlib import Path

from python import runfiles


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output-file", type=Path, required=True)
    args, _ = parser.parse_known_args()
    root = runfiles.CreateOrRaise().root()
    for location, expected in [
        ("_main/uv_wrapper/symlink_payload.txt", "symlink payload\n"),
        ("uv_wrapper/root_symlink_payload.txt", "root symlink payload\n"),
    ]:
        assert (root / location).read_text() == expected, location
    payload = root / "_main/tests/uv/lock/testdata/toolchain_payload.txt"
    args.output_file.write_bytes(payload.read_bytes())


if __name__ == "__main__":
    main()
