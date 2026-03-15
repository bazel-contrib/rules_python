import os

module_space = os.environ.get("RULES_PYTHON_TESTING_RUNFILES_ROOT")
print(f"inner: RULES_PYTHON_TESTING_RUNFILES_ROOT='{module_space}'")
