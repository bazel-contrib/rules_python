"""Check that the coverage is collected with the bundled coverage tool.

The tests run the instrumented program with the same environment variables
that `bazel coverage` sets and check the lcov file that it produces.
"""

import glob
import os
import pathlib
import subprocess
import unittest

from python.runfiles import runfiles

_LIB = "tests/coverage/lib.py"
_MAIN = "tests/coverage/instrumented.py"


def _parse_lcov(path):
    """Parse the line and branch coverage from an lcov file.

    Returns:
        A dict of the source file to a struct-like dict with the `lines`
        (line number to hit count) and `branches` (line number to the list of
        the branch hit counts).
    """
    result = {}
    current = None
    for line in pathlib.Path(path).read_text().splitlines():
        if line.startswith("SF:"):
            current = result.setdefault(
                line[len("SF:") :],
                {"lines": {}, "branches": {}},
            )
        elif current is None:
            continue
        elif line.startswith("DA:"):
            lineno, hits = line[len("DA:") :].split(",")[:2]
            current["lines"][int(lineno)] = int(hits)
        elif line.startswith("BRDA:"):
            lineno, _, _, taken = line[len("BRDA:") :].split(",")
            current["branches"].setdefault(int(lineno), []).append(
                0 if taken == "-" else int(taken)
            )
    return result


class CoverageCollectionTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        rf = runfiles.Create()
        assert rf is not None
        program = rf.Rlocation(os.environ["INSTRUMENTED"])
        assert program is not None and os.path.exists(program), program
        lib_path = rf.Rlocation("_main/" + _LIB)
        assert lib_path is not None
        cls.lib_lines = pathlib.Path(lib_path).read_text().splitlines()

        tmp = pathlib.Path(os.environ["TEST_TMPDIR"])
        coverage_dir = tmp / "coverage"
        coverage_dir.mkdir()
        manifest = tmp / "coverage_manifest.txt"
        # Like `bazel coverage`, list all of the instrumented files.
        manifest.write_text("\n".join([_LIB, _MAIN]) + "\n")

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

        cls.result = subprocess.run(
            [program],
            env=env,
            capture_output=True,
            text=True,
        )
        cls.lcov_files = glob.glob(str(coverage_dir / "pylcov_*.dat"))
        cls.lcov = _parse_lcov(cls.lcov_files[0]) if len(cls.lcov_files) == 1 else {}

    def _lineno(self, content):
        """Return the 1-based line number of the unique line in lib.py."""
        matches = [
            i + 1 for i, line in enumerate(self.lib_lines) if line.strip() == content
        ]
        self.assertEqual(len(matches), 1, f"'{content}' in {_LIB}: {matches}")
        return matches[0]

    def _line_hits(self, content):
        self.assertIn(_LIB, self.lcov, f"lcov: {self.lcov}")
        lineno = self._lineno(content)
        lines = self.lcov[_LIB]["lines"]
        self.assertIn(lineno, lines, f"line {lineno} '{content}' not in lcov: {lines}")
        return lines[lineno]

    def test_program_succeeds(self):
        self.assertEqual(
            self.result.returncode,
            0,
            f"stdout:\n{self.result.stdout}\nstderr:\n{self.result.stderr}",
        )
        self.assertEqual(self.result.stdout.splitlines(), ["truthy", "hello coverage"])

    def test_single_lcov_file_is_produced(self):
        self.assertEqual(
            len(self.lcov_files),
            1,
            f"lcov files: {self.lcov_files}\nstderr:\n{self.result.stderr}",
        )

    def test_instrumented_files_use_relative_paths(self):
        # NOTE: coverage.py also reports the files from the source directories
        # that were not imported, so only check the instrumented files.
        for path in [_LIB, _MAIN]:
            with self.subTest(path=path):
                self.assertIn(path, self.lcov, f"lcov files: {sorted(self.lcov)}")
                self.assertEqual(
                    [f for f in self.lcov if f != path and f.endswith("/" + path)],
                    [],
                )

    def test_executed_lines_are_covered(self):
        for content in [
            "if value:",
            'return "truthy"',
            'return "hello " + name',
        ]:
            with self.subTest(line=content):
                self.assertGreater(self._line_hits(content), 0)

    def test_definitions_are_covered(self):
        # Module level statements are executed on import.
        for content in [
            "def covered(value):",
            "def not_covered():",
            "class Greeter:",
            "def unused(self):",
        ]:
            with self.subTest(line=content):
                self.assertGreater(self._line_hits(content), 0)

    def test_skipped_branch_is_not_covered(self):
        self.assertEqual(self._line_hits('return "falsy"'), 0)

    def test_uncalled_function_is_not_covered(self):
        self.assertEqual(self._line_hits('return "never called"'), 0)

    def test_uncalled_method_is_not_covered(self):
        self.assertEqual(self._line_hits('return "unused method"'), 0)

    def test_partial_branch_coverage(self):
        lineno = self._lineno("if value:")
        branches = self.lcov[_LIB]["branches"]
        self.assertIn(lineno, branches, f"branches: {branches}")
        # Only the `True` branch of the `if` was taken.
        self.assertEqual(sorted(b > 0 for b in branches[lineno]), [False, True])
