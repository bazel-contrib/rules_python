import argparse
from pathlib import Path

from python import runfiles


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output-file", type=Path, required=True)
    args, _ = parser.parse_known_args()
    root = runfiles.CreateOrRaise().root()
    # Refer to the main repository by its apparent name so the paths resolve
    # under both bzlmod (`_main`) and WORKSPACE (`rules_python`).
    for location, expected in [
        ("rules_python/uv_wrapper/symlink_payload.txt", "symlink payload\n"),
        ("uv_wrapper/root_symlink_payload.txt", "root symlink payload\n"),
    ]:
        assert (root / location).read_text() == expected, location
    payload = root / "rules_python/tests/uv/lock/testdata/toolchain_payload.txt"
    args.output_file.write_bytes(payload.read_bytes())


if __name__ == "__main__":
    main()
