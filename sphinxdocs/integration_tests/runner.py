import logging
import os
import os.path
import pathlib
import re
import shlex
import subprocess
import unittest

_logger = logging.getLogger(__name__)


class ExecuteError(Exception):
    def __init__(self, result):
        self.result = result

    def __str__(self):
        return self.result.describe()


class ExecuteResult:
    def __init__(
        self,
        args: list[str],
        env: dict[str, str],
        cwd: pathlib.Path,
        proc_result: subprocess.CompletedProcess,
    ):
        self.args = args
        self.env = env
        self.cwd = cwd
        self.exit_code = proc_result.returncode
        self.stdout = proc_result.stdout
        self.stderr = proc_result.stderr

    def describe(self) -> str:
        env_lines = [
            "  " + shlex.quote(f"{key}={value}")
            for key, value in sorted(self.env.items())
        ]
        env = " \\\n".join(env_lines)
        args = shlex.join(self.args)
        maybe_stdout_nl = "" if self.stdout.endswith("\n") else "\n"
        maybe_stderr_nl = "" if self.stderr.endswith("\n") else "\n"
        return f"""\
COMMAND:
cd {self.cwd} && \\
env \\
{env} \\
  {args}
RESULT: exit_code: {self.exit_code}
===== STDOUT START =====
{self.stdout}{maybe_stdout_nl}===== STDOUT END   =====
===== STDERR START =====
{self.stderr}{maybe_stderr_nl}===== STDERR END   =====
"""


class TestCase(unittest.TestCase):
    def setUp(self):
        super().setUp()
        self.repo_root = pathlib.Path(os.environ["BIT_WORKSPACE_DIR"])
        self.bazel = pathlib.Path(os.environ["BIT_BAZEL_BINARY"])
        outer_test_tmpdir = pathlib.Path(os.environ["TEST_TMPDIR"])
        self.test_tmp_dir = outer_test_tmpdir / "bit_test_tmp"
        self.tmp_dir = outer_test_tmpdir / "bit_tmp"
        self.bazel_env = {
            "PATH": os.environ["PATH"],
            "TEST_TMPDIR": str(self.test_tmp_dir),
            "TMP": str(self.tmp_dir),
            "RUNFILES_DIR": os.environ["TEST_SRCDIR"],
        }

    def run_bazel(self, *args: str, check: bool = True) -> ExecuteResult:
        args = [str(self.bazel), *args]
        env = self.bazel_env
        _logger.info("executing: %s", shlex.join(args))
        cwd = self.repo_root
        proc_result = subprocess.run(
            args=args,
            text=True,
            capture_output=True,
            cwd=cwd,
            env=env,
            check=False,
        )
        exec_result = ExecuteResult(args, env, cwd, proc_result)
        if check and exec_result.exit_code:
            raise ExecuteError(exec_result)
        else:
            return exec_result

    def assert_result_matches(self, result: ExecuteResult, regex: str) -> None:
        if not re.search(regex, result.stdout + result.stderr):
            self.fail(
                "Bazel output did not match expected pattern\n"
                + f"expected pattern: {regex}\n"
                + f"invocation details:\n{result.describe()}"
            )
