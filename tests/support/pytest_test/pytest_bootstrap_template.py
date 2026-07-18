import sys

import pytest_bazel

TEST_FILES = """%TEST_FILES%""".splitlines()

args = sys.argv[1:] + TEST_FILES
sys.exit(pytest_bazel.main(args))
