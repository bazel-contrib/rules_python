import argparse
from pathlib import Path

from python import runfiles


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output-file", type=Path, required=True)
    args, _ = parser.parse_known_args()
    files = runfiles.Create()
    assert files is not None
    for location, expected in [
        ("_main/uv_wrapper/symlink_payload.txt", "symlink payload\n"),
        ("uv_wrapper/root_symlink_payload.txt", "root symlink payload\n"),
    ]:
        path = files.Rlocation(location)
        assert path is not None, location
        assert Path(path).read_text() == expected, location
    payload = files.Rlocation("_main/tests/uv/lock/testdata/toolchain_payload.txt")
    assert payload is not None
    args.output_file.write_bytes(Path(payload).read_bytes())


if __name__ == "__main__":
    main()
