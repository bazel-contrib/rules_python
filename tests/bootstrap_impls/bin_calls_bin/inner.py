import os

runfiles_root = os.environ.get("RULES_PYTHON_TESTING_RUNFILES_ROOT")
runfiles_dir = os.environ.get("RUNFILES_DIR")
runfiles_manifest_file = os.environ.get("RUNFILES_MANIFEST_FILE")
print(f"inner: RULES_PYTHON_TESTING_RUNFILES_ROOT='{runfiles_root}'")
print(f"inner: RUNFILES_DIR='{runfiles_dir}'")
print(f"inner: RUNFILES_MANIFEST_FILE='{runfiles_manifest_file}'")

try:
    import tests.bootstrap_impls.bin_calls_bin.inner_lib as inner_lib
    print(f"inner: import_result='{inner_lib.confirm()}'")
except ImportError as e:
    print(f"inner: import_result='{e}'")
