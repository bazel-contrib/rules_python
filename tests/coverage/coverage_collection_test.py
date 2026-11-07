"""Check that the coverage is collected with the bundled coverage tool.

The test runs the instrumented program with the same environment variables
that `bazel coverage` sets and checks the lcov file that it produces.
"""

import glob
import os
import pathlib
import subprocess
import unittest

from python.runfiles import runfiles

_LIB = "tests/coverage/lib.py"


def _parse_lcov(path):
    """Return a dict of the source file to a dict of line number to hit count."""
    result = {}
    current = None
    for line in pathlib.Path(path).read_text().splitlines():
        if line.startswith("SF:"):
            current = result.setdefault(line[len("SF:") :], {})
        elif line.startswith("DA:") and current is not None:
            lineno, hits = line[len("DA:") :].split(",")[:2]
            current[int(lineno)] = int(hits)
    return result


class CoverageCollectionTest(unittest.TestCase):
    def test_lcov_contains_line_coverage(self):
        rf = runfiles.Create()
        assert rf is not None
        program = rf.Rlocation(os.environ["INSTRUMENTED"])
        assert program is not None and os.path.exists(program), program

        coverage_dir = pathlib.Path(os.environ["TEST_TMPDIR"]) / "coverage"
        coverage_dir.mkdir()
        manifest = coverage_dir.parent / "coverage_manifest.txt"
        manifest.write_text(_LIB + "\n")

        # Do not leak the coverage settings of this test (e.g. when running
        # `bazel coverage`) into the instrumented program.
        env = {
            k: v
            for k, v in os.environ.items()
            if not k.startswith("COVERAGE") and k != "PYTHON_COVERAGE"
        }
        env.update(rf.EnvVars())
        env["COVERAGE"] = "1"
        env["COVERAGE_DIR"] = str(coverage_dir)
        env["COVERAGE_MANIFEST"] = str(manifest)

        workspace_dir = os.path.dirname(os.path.dirname(os.path.dirname(program)))
        result = subprocess.run(
            [program],
            cwd=workspace_dir,
            env=env,
            capture_output=True,
            text=True,
        )
        self.assertEqual(
            result.returncode,
            0,
            f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}",
        )
        self.assertIn("truthy", result.stdout)

        lcov_files = glob.glob(str(coverage_dir / "pylcov_*.dat"))
        self.assertEqual(
            len(lcov_files),
            1,
            f"lcov files: {lcov_files}\nstderr:\n{result.stderr}",
        )
        lcov = _parse_lcov(lcov_files[0])
        self.assertIn(_LIB, lcov, f"lcov: {lcov}")

        lib_path = rf.Rlocation("_main/" + _LIB)
        assert lib_path is not None
        lines = pathlib.Path(lib_path).read_text().splitlines()
        hits = {
            lines[lineno - 1].strip(): count for lineno, count in lcov[_LIB].items()
        }
        self.assertGreater(hits['return "truthy"'], 0, hits)
        self.assertEqual(hits['return "falsy"'], 0, hits)
        self.assertEqual(hits['return "never called"'], 0, hits)


if __name__ == "__main__":
    unittest.main()
