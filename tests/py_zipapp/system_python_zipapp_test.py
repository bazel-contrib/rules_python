import os
import signal
import subprocess
import sys
import tempfile
import time
import unittest


def _extract_root_from_output(output):
    for line in output.splitlines():
        if line.startswith("file:"):
            file_path = line.removeprefix("file:").strip()
            runfiles_marker = f"{os.sep}runfiles{os.sep}"
            if runfiles_marker in file_path:
                return file_path.split(runfiles_marker, 1)[0]
    raise AssertionError(f"Could not find file: line in output:\n{output}")


def _assert_removed_eventually(test, path):
    # Shell launchers exec the app and leave cleanup to a detached watcher.
    deadline = time.monotonic() + 15
    while os.path.exists(path):
        if time.monotonic() >= deadline:
            test.fail(f"Temporary zip extraction dir leaked after exit: {path}")
        time.sleep(0.1)


class SystemPythonZipAppTest(unittest.TestCase):
    def test_zipapp_cleans_readonly_files(self):
        output = subprocess.check_output(
            [os.environ["TEST_ZIPAPP"], "readonly-file"],
            stderr=subprocess.STDOUT,
            text=True,
        )
        _assert_removed_eventually(self, _extract_root_from_output(output))

    def test_zipapp_runnable(self):
        zipapp_path = os.environ["TEST_ZIPAPP"]

        self.assertTrue(os.path.exists(zipapp_path))
        self.assertTrue(os.path.isfile(zipapp_path))

        try:
            output = (
                subprocess.check_output([zipapp_path], stderr=subprocess.STDOUT)
                .decode("utf-8")
                .strip()
            )
        except subprocess.CalledProcessError as e:
            self.fail(
                "exit code: {}\n"
                " command: {}\n"
                "===== stdout/stderr start ==={}===== stdout/stderr end ====".format(
                    e.returncode, e.cmd, e.output.decode("utf-8")
                )
            )
        self.assertIn("Hello from zipapp", output)
        self.assertIn("dep:", output)
        self.assertIn(
            "xoption_zip_dir:UNSET",
            output,
            f"RULES_PYTHON_ZIP_DIR -X option leaked into user main.py:\n{output}",
        )

        extract_root = _extract_root_from_output(output)
        _assert_removed_eventually(self, extract_root)


@unittest.skipUnless(os.name == "posix", "POSIX signals are required")
class PosixSignalZipAppTest(unittest.TestCase):
    def zipapp_command(self, *args, invoke_with_python=False):
        zipapp_path = os.environ["TEST_ZIPAPP"]
        command = [zipapp_path]
        if invoke_with_python:
            command.insert(0, sys.executable)
        return [*command, *args]

    def start_signal_app(self, mode, invoke_with_python, preexec_fn=None):
        process = subprocess.Popen(
            self.zipapp_command(mode, invoke_with_python=invoke_with_python),
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            preexec_fn=preexec_fn,
        )
        self.assertIsNotNone(process.stdout)
        file_line = process.stdout.readline().strip()
        self.assertTrue(file_line.startswith("file:"), file_line)
        extract_root = _extract_root_from_output(file_line)
        ready = process.stdout.readline().strip()
        self.assertTrue(ready.startswith("ready:"), ready)
        return process, int(ready.removeprefix("ready:")), extract_root

    def stop_process(self, process, application_pid):
        if process.poll() is None:
            process.kill()
            process.wait()
        try:
            os.kill(application_pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        if process.stdout is not None:
            process.stdout.close()

    def test_zipapp_forwards_sigterm(self):
        for invoke_with_python in (False, True):
            with self.subTest(invoke_with_python=invoke_with_python):
                process, application_pid, extract_root = self.start_signal_app(
                    "wait-for-sigterm", invoke_with_python
                )
                try:
                    process.terminate()
                    output, _ = process.communicate(timeout=10)
                    self.assertEqual(0, process.returncode, output)
                    self.assertIn(f"received:{signal.SIGTERM}", output)
                    _assert_removed_eventually(self, extract_root)
                finally:
                    self.stop_process(process, application_pid)

    def test_zipapp_preserves_signal_termination(self):
        for invoke_with_python in (False, True):
            with self.subTest(invoke_with_python=invoke_with_python):
                process, application_pid, extract_root = self.start_signal_app(
                    "wait-for-unhandled-sigterm", invoke_with_python
                )
                try:
                    process.terminate()
                    output, _ = process.communicate(timeout=10)
                    expected = (
                        128 + signal.SIGTERM if invoke_with_python else -signal.SIGTERM
                    )
                    self.assertEqual(expected, process.returncode, output)
                    _assert_removed_eventually(self, extract_root)
                finally:
                    self.stop_process(process, application_pid)

    def test_zipapp_preserves_extract_root_cache(self):
        for invoke_with_python in (False, True):
            with self.subTest(invoke_with_python=invoke_with_python):
                with tempfile.TemporaryDirectory() as extract_root_env:
                    env = {**os.environ, "RULES_PYTHON_EXTRACT_ROOT": extract_root_env}
                    proc = subprocess.run(
                        self.zipapp_command(invoke_with_python=invoke_with_python),
                        env=env,
                        stdout=subprocess.PIPE,
                        stderr=subprocess.STDOUT,
                        text=True,
                        check=True,
                    )
                    extract_root = _extract_root_from_output(proc.stdout)
                    self.assertTrue(
                        extract_root.startswith(extract_root_env),
                        f"Expected {extract_root} to be under {extract_root_env}",
                    )
                    self.assertTrue(
                        os.path.exists(extract_root),
                        f"RULES_PYTHON_EXTRACT_ROOT cache dir was unexpectedly deleted: {extract_root}",
                    )
                    self.assertIn(
                        "xoption_zip_dir:UNSET",
                        proc.stdout,
                        "RULES_PYTHON_ZIP_DIR should not be exposed when "
                        f"RULES_PYTHON_EXTRACT_ROOT is set:\n{proc.stdout}",
                    )

    def test_zipapp_preserves_sig_ign(self):
        sighup = getattr(signal, "SIGHUP")
        for invoke_with_python in (False, True):
            with self.subTest(invoke_with_python=invoke_with_python):
                process, application_pid, _ = self.start_signal_app(
                    "wait-for-unhandled-sigterm",
                    invoke_with_python,
                    preexec_fn=lambda: signal.signal(sighup, signal.SIG_IGN),
                )
                try:
                    process.send_signal(sighup)
                    time.sleep(0.2)
                    self.assertIsNone(
                        process.poll(),
                        f"Process died from SIGHUP (returncode={process.returncode}) instead of ignoring SIG_IGN",
                    )
                    process.terminate()
                    output, _ = process.communicate(timeout=10)
                    expected = (
                        128 + signal.SIGTERM if invoke_with_python else -signal.SIGTERM
                    )
                    self.assertEqual(
                        expected,
                        process.returncode,
                        f"Process died from SIGHUP instead of ignoring SIG_IGN:\n{output}",
                    )
                finally:
                    self.stop_process(process, application_pid)

    def test_zipapp_preserves_nonzero_exit_status(self):
        for invoke_with_python in (False, True):
            with self.subTest(invoke_with_python=invoke_with_python):
                process = subprocess.run(
                    self.zipapp_command(
                        "exit", "17", invoke_with_python=invoke_with_python
                    ),
                    check=False,
                )
                self.assertEqual(17, process.returncode)

    def test_zipapp_inherits_ignored_signals(self):
        def ignore_signals():
            for name in ("SIGHUP", "SIGINT", "SIGQUIT", "SIGTERM"):
                signal.signal(getattr(signal, name), signal.SIG_IGN)

        for invoke_with_python in (False, True):
            with self.subTest(invoke_with_python=invoke_with_python):
                process = subprocess.run(
                    self.zipapp_command(
                        "check-ignored-signals", invoke_with_python=invoke_with_python
                    ),
                    preexec_fn=ignore_signals,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.STDOUT,
                    text=True,
                    timeout=10,
                    check=True,
                )
                self.assertIn("ignored-signals:True", process.stdout)


if __name__ == "__main__":
    unittest.main()
