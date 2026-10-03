import os
import signal
import subprocess
import time
import unittest

# How long to wait for the extracted files to be removed after the zipapp exits.
_CLEANUP_TIMEOUT_SECONDS = 15


class ZipAppSignalsTest(unittest.TestCase):
    def setUp(self):
        self.zipapp_path = os.environ["TEST_ZIPAPP"]

    def _start(self):
        proc = subprocess.Popen([self.zipapp_path], stdout=subprocess.PIPE, text=True)
        self.addCleanup(self._kill, proc)
        assert proc.stdout is not None
        pid_line = proc.stdout.readline().strip()
        zip_dir_line = proc.stdout.readline().strip()
        if not pid_line.startswith("pid=") or not zip_dir_line.startswith("zip_dir="):
            self.fail(f"unexpected zipapp output: {pid_line!r} {zip_dir_line!r}")
        pid = int(pid_line.split("=", 1)[1])
        # If the launcher doesn't exec, the Python process outlives it and keeps
        # stdout open, so make sure it's killed too.
        self.addCleanup(self._kill_pid, pid)
        zip_dir = zip_dir_line.split("=", 1)[1]
        self.assertTrue(os.path.isdir(zip_dir), f"{zip_dir} does not exist")
        return proc, pid, zip_dir

    def _kill(self, proc):
        if proc.poll() is None:
            proc.kill()
        try:
            proc.communicate(timeout=10)
        except subprocess.TimeoutExpired:
            pass

    def _kill_pid(self, pid):
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass

    def assertRemovedEventually(self, path):
        deadline = time.monotonic() + _CLEANUP_TIMEOUT_SECONDS
        while os.path.exists(path):
            if time.monotonic() > deadline:
                self.fail(f"{path} was not removed after the zipapp exited")
            time.sleep(0.2)

    def test_signal_reaches_python_process(self):
        proc, pid, zip_dir = self._start()
        # The launcher must exec the interpreter, so the PID the caller started
        # is the Python process and signals sent to it are delivered there.
        self.assertEqual(pid, proc.pid)

        proc.send_signal(signal.SIGTERM)
        output, _ = proc.communicate(timeout=30)

        self.assertIn("got SIGTERM", output)
        self.assertEqual(proc.returncode, 0)
        self.assertRemovedEventually(zip_dir)

    def test_extracted_files_removed_after_sigkill(self):
        proc, _, zip_dir = self._start()

        proc.kill()
        proc.communicate(timeout=30)

        self.assertRemovedEventually(zip_dir)

    def test_exit_code_is_propagated(self):
        result = subprocess.run([self.zipapp_path, "--exit-code=3"], timeout=60)

        self.assertEqual(result.returncode, 3)


if __name__ == "__main__":
    unittest.main()
