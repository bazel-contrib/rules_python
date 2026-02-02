import json
import sys
import datetime
import tomllib


def json_serializer(obj):
    if isinstance(obj, datetime.datetime):
        return obj.isoformat()
    raise TypeError(f"Object of type {type(obj).__name__} is not JSON serializable")


def main():
    if len(sys.argv) < 2:
        print("Usage: toml2json <toml_file>", file=sys.stderr)
        sys.exit(1)

    toml_file_path = sys.argv[1]

    try:
        with open(toml_file_path, "rb") as f:
            data = tomllib.load(f)
            json.dump(data, sys.stdout, indent=2, default=json_serializer)
            print()
    except FileNotFoundError:
        print(f"Error: File not found: {toml_file_path}", file=sys.stderr)
        sys.exit(1)
    except tomllib.TOMLDecodeError as e:
        print(f"Error decoding TOML: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
