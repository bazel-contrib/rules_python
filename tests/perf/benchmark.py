"""Print the number of steps that the workloads take as a Markdown table.

    bazel run //tests/perf:benchmark

See the README.md for details.
"""

import sys

from tests.perf import starlark_shim
from tests.perf.workloads import workloads


def main(argv):
    only = argv[0] if argv else ""
    print("| Workload | Steps |")
    print("|---|---:|")
    for name, fn in workloads().items():
        if only in name:
            print("| `{}` | {} |".format(name, starlark_shim.count_steps(fn)))


if __name__ == "__main__":
    main(sys.argv[1:])
