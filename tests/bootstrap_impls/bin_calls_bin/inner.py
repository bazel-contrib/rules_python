import os

runfiles_root = os.environ.get("RULES_PYTHON_TESTING_RUNFILES_ROOT")
print(f"inner: RULES_PYTHON_TESTING_RUNFILES_ROOT='{runfiles_root}'")
