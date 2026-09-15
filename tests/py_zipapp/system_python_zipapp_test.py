import os
import signal
import subprocess
import sys
import unittest


class SystemPythonZipAppTest(unittest.TestCase):
    def zipapp_command(self, *args, invoke_with_python=False):
        zipapp_path = os.environ["TEST_ZIPAPP"]
        command = [zipapp_path]
        if invoke_with_python:
            command.insert(0, sys.executable)
        return [*command, *args]

    def start_signal_app(self, mode, invoke_with_python):
        process = subprocess.Popen(
            self.zipapp_command(mode, invoke_with_python=invoke_with_python),
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
        )
        self.assertIsNotNone(process.stdout)
        ready = process.stdout.readline().strip()
        self.assertTrue(ready.startswith("ready:"), ready)
        return process, int(ready.removeprefix("ready:"))

    def stop_process(self, process, application_pid):
        if process.poll() is None:
            process.kill()
            process.wait()
        try:
            os.kill(application_pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        if process.stdout is not None:
            process.stdout.close()

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

    @unittest.skipIf(os.name == "nt", "POSIX signals are required")
    def test_zipapp_forwards_sigterm(self):
        for invoke_with_python in (False, True):
            with self.subTest(invoke_with_python=invoke_with_python):
                process, application_pid = self.start_signal_app(
                    "wait-for-sigterm", invoke_with_python
                )
                try:
                    process.terminate()
                    output, _ = process.communicate(timeout=10)
                    self.assertEqual(0, process.returncode, output)
                    self.assertIn(f"received:{signal.SIGTERM}", output)
                finally:
                    self.stop_process(process, application_pid)

    @unittest.skipIf(os.name == "nt", "POSIX signals are required")
    def test_zipapp_preserves_signal_termination(self):
        for invoke_with_python in (False, True):
            with self.subTest(invoke_with_python=invoke_with_python):
                process, application_pid = self.start_signal_app(
                    "wait-for-unhandled-sigterm", invoke_with_python
                )
                try:
                    process.terminate()
                    output, _ = process.communicate(timeout=10)
                    expected = (
                        128 + signal.SIGTERM if invoke_with_python else -signal.SIGTERM
                    )
                    self.assertEqual(expected, process.returncode, output)
                finally:
                    self.stop_process(process, application_pid)

    @unittest.skipIf(os.name == "nt", "POSIX signals are required")
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


if __name__ == "__main__":
    unittest.main()
