"""Tests that the Starlark code does not get slower without us noticing."""

import unittest

from tests.perf import starlark_shim
from tests.perf.workloads import workloads

# The number of steps that each workload takes, see the README.md. Update the
# numbers with the output of `bazel run //tests/perf:benchmark`.
_STEPS = {
    # keep sorted
    "evaluate_long": 6376,
    "evaluate_non_strict": 703,
    "evaluate_string": 362,
    "evaluate_two_strings": 750,
    "evaluate_version": 525,
    "tokenize_long": 4870,
    "tokenize_no_whitespace": 563,
    "tokenize_version": 305,
    "version_is_compatible": 64,
    "version_is_eq_prefix": 10,
    "version_is_ge": 54,
    "version_is_lt": 48,
    "version_key": 26,
    "version_normalize": 24,
    "version_parse_all_segments": 1518,
    "version_parse_invalid": 632,
    "version_parse_pre_release": 1020,
    "version_parse_prefix": 52,
    "version_parse_release": 53,
}

# The number of the steps slightly depends on the Python version.
_TOLERANCE = 0.05


class StepsTest(unittest.TestCase):
    def test_all_workloads_are_measured(self):
        self.assertEqual(sorted(_STEPS), sorted(workloads()))

    def test_steps(self):
        for name, fn in workloads().items():
            with self.subTest(name):
                want = _STEPS[name]
                self.assertAlmostEqual(
                    starlark_shim.count_steps(fn),
                    want,
                    delta=want * _TOLERANCE,
                    msg="The number of steps has changed, see tests/perf/README.md",
                )


if __name__ == "__main__":
    unittest.main()
