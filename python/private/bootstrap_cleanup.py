"""Remove a temporary runtime after the exec'ed launcher's process exits.

This runs with -I -S, outside the application's process group. The direct child
exits successfully only after an orphaned watcher is armed, so stage one can
reap it before exec. Deletion is asynchronous.

Namespace PID 1 and subreapers can adopt the watcher; namespace shutdown can
kill it before removal finishes. Persistent runtime-venv extract roots avoid
this helper; legacy executable ZIPs always extract to temporary directories.
"""

import contextlib
import errno
import os
import resource
import select
import shutil
import socket
import sys
import time


def _close_inherited_fds():
    # Existing descriptors can be above a limit lowered by the caller. Prefer
    # enumerating them to scanning every number up to the resource limit.
    for directory in ("/proc/self/fd", "/dev/fd"):
        try:
            descriptors = os.listdir(directory)
        except OSError:
            continue
        for name in descriptors:
            if name.isdigit() and int(name) > 2:
                with contextlib.suppress(OSError):
                    os.close(int(name))
        return
    _, hard_limit = resource.getrlimit(resource.RLIMIT_NOFILE)
    # Without a descriptor directory, POSIX cannot recover limits that the
    # caller lowered below already-open descriptors. Use the current hard limit.
    if hard_limit == resource.RLIM_INFINITY:
        hard_limit = os.sysconf("SC_OPEN_MAX")
    os.closerange(3, hard_limit)


def _poll_pid(pid):
    # Last resort on systems without a native watch or Linux procfs. PID reuse
    # can delay removal, but must never remove the runtime while that PID lives.
    while True:
        try:
            os.kill(pid, 0)
        except ProcessLookupError:
            return
        except PermissionError:
            pass
        time.sleep(0.1)


def _arm_poll_watch(pid, resources):
    try:
        # An ancestor namespace's procfs can map this PID to another process.
        if os.readlink("/proc/self") != str(os.getpid()) or os.readlink(
            "/proc/self/ns/pid"
        ) != os.readlink("/proc/1/ns/pid"):
            return lambda: _poll_pid(pid)
        fd = os.open("/proc/{}/stat".format(pid), os.O_RDONLY)
    except OSError:
        return lambda: _poll_pid(pid)
    resources.callback(os.close, fd)

    def wait():
        # An open Linux proc descriptor stays tied to the original process,
        # even if its PID is reused. Wait for reaping: a zombie group leader
        # can still have live worker threads that need the runtime.
        while True:
            try:
                os.lseek(fd, 0, os.SEEK_SET)
                data = os.read(fd, 4096)
            except ProcessLookupError:
                return
            if not data:
                return _poll_pid(pid)
            time.sleep(0.1)

    return wait


def _arm_watch(pid, resources):
    try:
        if hasattr(os, "pidfd_open"):
            fd = os.pidfd_open(pid)
            resources.callback(os.close, fd)

            def wait():
                select.select([fd], [], [])

        elif hasattr(select, "kqueue"):
            queue = select.kqueue()
            resources.callback(queue.close)
            event = select.kevent(
                pid,
                filter=select.KQ_FILTER_PROC,
                flags=select.KQ_EV_ADD | select.KQ_EV_ONESHOT,
                fflags=select.KQ_NOTE_EXIT,
            )
            queue.control([event], 0, 0)

            def wait():
                queue.control(None, 1)

        else:
            return _arm_poll_watch(pid, resources)
    except OSError as error:
        if error.errno == errno.ESRCH:
            return lambda: None
        if error.errno not in (errno.ENOSYS, errno.ENOTSUP, errno.EINVAL, errno.EPERM):
            raise
        return _arm_poll_watch(pid, resources)

    return wait


def _watch(pid, runtimes, control):
    # Do not hold the caller's output open, including during handshake failure.
    os.dup2(0, 1)
    os.dup2(0, 2)
    with control, contextlib.ExitStack() as resources:
        wait = _arm_watch(pid, resources)
        permission = b""
        try:
            control.sendall(b"A")  # The process watch is armed.
            permission = control.recv(1)
        except OSError:
            pass
        # Only the direct child can confirm that its actual parent exited.
        # EOF, invalid data, or a dead helper cannot authorize early removal.
        if permission != b"E":
            try:
                wait()
            except OSError:
                _poll_pid(pid)

    # All cleanup dependencies are imported before any runtime can be removed.
    for runtime in reversed(runtimes):
        shutil.rmtree(runtime, ignore_errors=True)


def main():
    parent_pid = int(sys.argv[1])
    runtimes = [os.path.abspath(path) for path in sys.argv[2:]]

    # Inherited pipes and locks must not outlive the application. Keep stderr
    # for setup diagnostics until the watcher forks.
    _close_inherited_fds()
    os.setsid()
    null_fd = os.open(os.devnull, os.O_RDWR)
    os.dup2(null_fd, 0)
    os.dup2(0, 1)
    # Reserve standard descriptors before creating the watch: the caller may
    # have closed stdin or stderr, and a watch must never occupy those slots.
    try:
        os.fstat(2)
    except OSError as error:
        if error.errno != errno.EBADF:
            raise
        os.dup2(0, 2)
    if null_fd > 2:
        os.close(null_fd)
    os.chdir("/")

    if os.getppid() != parent_pid:
        for runtime in reversed(runtimes):
            shutil.rmtree(runtime, ignore_errors=True)
        return 1

    parent, watcher = socket.socketpair()
    if os.fork() == 0:
        parent.close()
        _watch(parent_pid, runtimes, watcher)
        return 0

    watcher.close()
    with parent:
        if parent.recv(1) != b"A":
            return 1
        # Check real parent identity after watch registration. If the original
        # launcher exited during setup, the watch may refer to a reused PID.
        alive = os.getppid() == parent_pid
        parent.sendall(b"W" if alive else b"E")
        return 0 if alive else 1


if __name__ == "__main__":
    sys.exit(main())
