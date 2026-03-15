import os
import subprocess
import sys

if __name__ == "__main__":
    runfiles_root = os.environ.get("RULES_PYTHON_TESTING_RUNFILES_ROOT")
    print(f"outer: RULES_PYTHON_TESTING_RUNFILES_ROOT='{runfiles_root}'")

    inner_binary_path = sys.argv[1]
    result = subprocess.run(
        [inner_binary_path],
        capture_output=True,
        text=True,
        check=True,
    )
    print(result.stdout, end="")
    if result.stderr:
        print(result.stderr, end="", file=sys.stderr)
