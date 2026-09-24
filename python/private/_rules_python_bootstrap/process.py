"""Preparation cancellation, owned setup children, and platform launch."""

import contextlib
import os
import signal
import subprocess
import sys

from .diagnostics import verbose


class Cancelled(BaseException):
    def __init__(self, signum):
        self.signum = signum


class Cancellation:
    """Record cancellation; raise only at explicit resource-safe boundaries."""

    def __init__(self):
        self.pending = None
        self.handlers = {}
        self.mask = None

    def __enter__(self):
        signals = [signal.SIGINT]
        if os.name == "posix":
            signals += [signal.SIGTERM, signal.SIGHUP, signal.SIGQUIT]
            self.mask = signal.pthread_sigmask(signal.SIG_BLOCK, [])
        for signum in signals:
            previous = signal.getsignal(signum)
            if previous != signal.SIG_IGN:
                self.handlers[signum] = previous
                signal.signal(signum, self._record)
        return self

    def _record(self, signum, _frame):
        if self.pending is None:
            self.pending = signum

    def check(self):
        if self.pending is not None:
            raise Cancelled(self.pending)

    def restore(self):
        for signum, previous in self.handlers.items():
            signal.signal(signum, previous)
        if os.name == "posix" and self.mask is not None:
            signal.pthread_sigmask(signal.SIG_SETMASK, self.mask)

    def prepare_exec(self):
        if os.name == "posix":
            assert self.mask is not None, "POSIX cancellation context was not entered"
            # Stop recording cancellation before restoring the caller's mask.
            # Pending kernel signals then see the caller's dispositions; requests
            # already recorded by Python are checked after every handler is restored.
            signal.pthread_sigmask(signal.SIG_BLOCK, self.handlers)
            self.check()
            for signum, previous in self.handlers.items():
                signal.signal(signum, previous)
            self.check()
            signal.pthread_sigmask(signal.SIG_SETMASK, self.mask)
        else:
            raise RuntimeError("Native exec requires a POSIX cancellation context")

    def __exit__(self, _kind, error, _traceback):
        self.restore()
        if isinstance(error, Cancelled):
            if os.name == "posix":
                signal.signal(error.signum, signal.SIG_DFL)
                os.kill(os.getpid(), error.signum)
            raise SystemExit(128 + error.signum)


def run_child(argv, cancellation, *, capture=False, **kwargs):
    """Keep setup children owned through cancellation and reap before rollback."""
    cancellation.check()
    child = subprocess.Popen(
        argv, stdout=subprocess.PIPE if capture else None, **kwargs
    )
    try:
        while True:
            cancellation.check()
            try:
                output, _ = child.communicate(timeout=0.1)
                break
            except subprocess.TimeoutExpired:
                continue
        cancellation.check()
        if child.returncode:
            raise subprocess.CalledProcessError(child.returncode, argv, output)
        return output
    finally:
        if child.poll() is None:
            child.kill()
        child.wait()


def execute(command, workspace, cleanup_helper, cancellation):
    """Transfer temporary ownership before native exec; Windows waits locally."""
    cancellation.check()
    verbose("launching interpreter", command.executable)
    if os.name == "nt":
        child = subprocess.Popen(command.argv, env=command.environment, cwd=command.cwd)
        try:
            cancellation.check()
            # Windows delivers console Ctrl-C to both processes. Keep recording
            # it here without terminating the application's own cleanup or
            # forwarding a second interrupt. The application chooses its status.
            status = child.wait()
            # Older CPython sys.exit converts through a signed 32-bit C long.
            return status if status < 0x80000000 else status - 0x100000000
        finally:
            if child.poll() is None:
                child.kill()
            child.wait()

    if workspace.path and not workspace.retain:
        run_child(
            [
                command.executable,
                "-I",
                "-S",
                cleanup_helper,
                str(os.getpid()),
                workspace.path,
            ],
            cancellation,
        )
    if command.cwd is not None:
        os.chdir(command.cwd)
    for stream in (sys.stdout, sys.stderr):
        if stream is not None:
            with contextlib.suppress(OSError, ValueError):
                stream.flush()
    cancellation.prepare_exec()
    os.execve(command.executable, command.argv, command.environment)
