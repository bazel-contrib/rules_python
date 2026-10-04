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

    def _start(self, new_session=False):
        proc = subprocess.Popen(
            [self.zipapp_path],
            stdout=subprocess.PIPE,
            text=True,
            start_new_session=new_session,
        )
        self.addCleanup(self._kill, proc)
        assert proc.stdout is not None
        pid_line = proc.stdout.readline().strip()
        zip_dir_line = proc.stdout.readline().strip()
        if not pid_line.startswith("pid=") or not zip_dir_line.startswith("zip_dir="):
            self.fail(f"unexpected zipapp output: {pid_line!r} {zip_dir_line!r}")
        pid = int(pid_line.split("=", 1)[1])
        if pid != proc.pid:
            # The launcher didn't exec, so the Python process can outlive it and
            # keep stdout open. Make sure it's killed too.
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

    def test_extracted_files_removed_before_process_is_reaped(self):
        proc, _, zip_dir = self._start()

        # Leave the exited process as a zombie: cleanup must not wait for the
        # caller to reap it.
        os.kill(proc.pid, signal.SIGKILL)

        self.assertRemovedEventually(zip_dir)

    def test_extracted_files_removed_after_process_group_signal(self):
        # A terminal's Ctrl-C (SIGINT), hangup (SIGHUP) or a supervisor stopping
        # the whole process group (SIGTERM) signals every process in the group,
        # including the cleanup watcher, which must survive to do its job.
        for sig in (signal.SIGINT, signal.SIGHUP, signal.SIGTERM):
            with self.subTest(signal=sig.name):
                proc, _, zip_dir = self._start(new_session=True)

                os.killpg(proc.pid, sig)
                proc.communicate(timeout=30)

                self.assertRemovedEventually(zip_dir)

    def test_exit_code_is_propagated(self):
        result = subprocess.run([self.zipapp_path, "--exit-code=3"], timeout=60)

        self.assertEqual(result.returncode, 3)


if __name__ == "__main__":
    unittest.main()
