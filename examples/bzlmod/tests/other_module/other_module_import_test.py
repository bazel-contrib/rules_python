"""Regression test for https://github.com/bazel-contrib/rules_python/issues/3563"""
import os
import subprocess
import sys

def main():
    # The rlocation path for the bin_zipapp. It is in the "our_other_module" repository.
    zipapp_path = os.environ.get("ZIPAPP_PATH")
    print(f"Running bin_zipapp at: {zipapp_path}")

    result = subprocess.run([zipapp_path], capture_output=True, text=True)
    print("--- bin_zippapp stdout ---")
    print(result.stdout)
    print("--- bin_zippapp stderr ---")
    print(result.stderr)

    if result.returncode != 0:
        print(f"bin_zippapp failed with return code {result.returncode}")
        sys.exit(result.returncode)

if __name__ == "__main__":
    main()
