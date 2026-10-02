"""Exit-watch races and fallbacks, separate from generated launcher tests."""

import contextlib
import errno
import os
import runpy
import subprocess
import sys
import time

import pytest

from python.runfiles import runfiles


@pytest.fixture(name="helper")
def fixture_helper():
    location = runfiles.CreateOrRaise().Rlocation(os.environ["HELPER_RLOCATION"])
    assert location is not None
    return location, runpy.run_path(location)


def test_parent_already_exited(helper, monkeypatch):
    _, support = helper

    def exited(_pid):
        raise ProcessLookupError(errno.ESRCH, "parent exited")

    monkeypatch.setattr(os, "pidfd_open", exited, raising=False)
    with contextlib.ExitStack() as resources:
        support["_arm_watch"](os.getppid(), resources)()


@pytest.mark.parametrize("error", [errno.ENOSYS, errno.EPERM, errno.EINVAL])
def test_native_watch_unavailable_uses_conservative_pid_poll(
    helper, monkeypatch, error
):
    _, support = helper

    def unavailable(_pid):
        raise OSError(error, "unavailable")

    monkeypatch.setattr(os, "pidfd_open", unavailable, raising=False)
    monkeypatch.setattr(os, "readlink", lambda _path: str(os.getpid()))
    monkeypatch.setattr(os, "open", lambda *args: unavailable(0))
    results = iter([None, PermissionError(), None, ProcessLookupError()])

    def exists(_pid, _signal):
        result = next(results)
        if result is not None:
            raise result

    monkeypatch.setattr(os, "kill", exists)
    with contextlib.ExitStack() as resources:
        support["_arm_watch"](os.getppid(), resources)()


def test_pidfd_readiness_and_descriptor_cleanup(helper, monkeypatch):
    _, support = helper
    read_fd, write_fd = os.pipe()
    os.close(write_fd)
    monkeypatch.setattr(os, "pidfd_open", lambda _pid: read_fd, raising=False)
    with contextlib.ExitStack() as resources:
        support["_arm_watch"](os.getppid(), resources)()
    with pytest.raises(OSError):
        os.fstat(read_fd)


@pytest.mark.parametrize(
    "backend",
    [
        pytest.param(
            "pidfd",
            marks=pytest.mark.skipif(
                sys.platform != "linux" or not hasattr(os, "pidfd_open"),
                reason="Linux pidfd contract",
            ),
        ),
        pytest.param(
            "proc",
            marks=pytest.mark.skipif(
                sys.platform != "linux", reason="Linux procfs contract"
            ),
        ),
        pytest.param(
            "kqueue",
            marks=pytest.mark.skipif(
                sys.platform != "darwin", reason="macOS kqueue contract"
            ),
        ),
    ],
)
def test_native_exit_watch_waits_and_closes_descriptor(helper, backend):
    path, _ = helper
    driver = """
import contextlib, errno, os, runpy, select, subprocess, sys, threading
support = runpy.run_path(sys.argv[1])
backend = sys.argv[2]
descriptors = []
with subprocess.Popen([sys.executable, '-c', 'import sys; sys.stdin.read()'],
                      stdin=subprocess.PIPE) as child:
    # Check host support independently so unsupported kernels or namespaces
    # are reported explicitly, instead of silently exercising a fallback.
    try:
        if backend == 'pidfd':
            os.close(os.pidfd_open(child.pid))
        elif backend == 'proc':
            if (os.readlink('/proc/self') != str(os.getpid()) or
                os.readlink('/proc/self/ns/pid') != os.readlink('/proc/1/ns/pid')):
                raise OSError(errno.ENOTSUP, 'procfs is from another namespace')
            os.close(os.open('/proc/%d/stat' % child.pid, os.O_RDONLY))
        else:
            with contextlib.closing(select.kqueue()) as queue:
                queue.control([select.kevent(child.pid, filter=select.KQ_FILTER_PROC,
                    flags=select.KQ_EV_ADD | select.KQ_EV_ONESHOT,
                    fflags=select.KQ_NOTE_EXIT)], 0, 0)
    except OSError as error:
        if error.errno not in (errno.ENOSYS, errno.ENOTSUP, errno.EPERM, errno.EACCES):
            raise
        print(str(error), file=sys.stderr)
        child.terminate()
        child.wait(timeout=5)
        sys.exit(77)

    def unexpected_fallback(*args):
        raise AssertionError('native watch unexpectedly used a fallback')

    support['_arm_watch'].__globals__['_poll_pid'] = unexpected_fallback
    if backend == 'proc':
        arm = support['_arm_poll_watch']
        create = os.open
        def open_proc(*args):
            fd = create(*args)
            descriptors.append(fd)
            return fd
        os.open = open_proc
    else:
        arm = support['_arm_watch']
        arm.__globals__['_arm_poll_watch'] = unexpected_fallback
        if backend == 'pidfd':
            create = os.pidfd_open
            def open_pidfd(pid):
                fd = create(pid)
                descriptors.append(fd)
                return fd
            os.pidfd_open = open_pidfd
        else:
            create = select.kqueue
            def open_queue():
                queue = create()
                descriptors.append(queue.fileno())
                return queue
            select.kqueue = open_queue

    finished = threading.Event()
    errors = []
    with contextlib.ExitStack() as resources:
        wait = arm(child.pid, resources)
        assert len(descriptors) == 1, 'expected backend did not register a watch'
        def observe():
            try:
                wait()
            except BaseException as error:
                errors.append(error)
            finally:
                finished.set()
        thread = threading.Thread(target=observe, daemon=True)
        thread.start()
        assert not finished.wait(.1), 'watch returned before application exit'
        child.terminate()
        child.wait(timeout=5)
        assert finished.wait(5), 'watch did not observe application exit'
        thread.join()
        assert not errors, errors
    try:
        os.fstat(descriptors[0])
    except OSError as error:
        assert error.errno == errno.EBADF
    else:
        raise AssertionError('watch descriptor remained open')
"""
    result = subprocess.run(
        [sys.executable, "-c", driver, path, backend],
        capture_output=True,
        text=True,
        timeout=20,
    )
    if result.returncode == 77:
        pytest.skip(f"{backend} unavailable on this host: {result.stderr.strip()}")
    assert result.returncode == 0, result.stderr


def test_unexpected_setup_error_is_reported(helper, monkeypatch):
    _, support = helper

    def failure(_pid):
        raise OSError(errno.EIO, "watch registration failed")

    monkeypatch.setattr(os, "pidfd_open", failure, raising=False)
    with contextlib.ExitStack() as resources, pytest.raises(
        OSError, match="watch registration failed"
    ):
        support["_arm_watch"](os.getppid(), resources)


@pytest.mark.parametrize("state", [b"Z", b"X"])
def test_proc_watch_waits_for_original_process_reaping(
    helper, tmp_path, monkeypatch, state
):
    _, support = helper
    path = tmp_path / "proc-stat"
    path.write_bytes(b"")
    fd = os.open(path, os.O_RDONLY)
    monkeypatch.setattr(os, "readlink", lambda _path: str(os.getpid()))
    monkeypatch.setattr(os, "open", lambda *_args: fd)
    records = iter([b"123 (a process) name) S 1", state, "gone"])
    observed = []

    def read(_fd, _length):
        assert _fd == fd
        value = next(records)
        observed.append(value)
        if value == "gone":
            raise ProcessLookupError(errno.ESRCH, "original process exited")
        if value in (b"Z", b"X"):
            return b"123 (a process) name) " + value + b" 1"
        return value

    monkeypatch.setattr(os, "read", read)
    with contextlib.ExitStack() as resources:
        support["_arm_poll_watch"](123, resources)()
    assert observed[-1] == "gone", "zombie leader can still have live threads"
    with pytest.raises(OSError):
        os.fstat(fd)


def test_proc_from_another_pid_namespace_uses_pid_poll(helper, monkeypatch):
    _, support = helper
    monkeypatch.setattr(
        os,
        "readlink",
        lambda path: (
            str(os.getpid())
            if path == "/proc/self"
            else ("pid:[100]" if path == "/proc/self/ns/pid" else "pid:[200]")
        ),
    )
    checked = []
    support["_arm_poll_watch"].__globals__["_poll_pid"] = checked.append
    with contextlib.ExitStack() as resources:
        support["_arm_poll_watch"](123, resources)()
    assert checked == [123]


@pytest.mark.parametrize("message", ["", "invalid", "closed_before_ready"])
def test_failed_control_handshake_does_not_remove_live_runtime(
    helper, tmp_path, message
):
    path, _ = helper
    runtime = tmp_path / "runtime"
    runtime.mkdir()
    driver = """
import os, runpy, socket, sys, time
support = runpy.run_path(sys.argv[1])
parent_pid = os.getpid()
parent, watcher = socket.socketpair()
child = os.fork()
if child == 0:
    parent.close()
    os.setsid()
    fd = os.open(os.devnull, os.O_RDWR)
    os.dup2(fd, 0)
    os.close(fd)
    support['_watch'](parent_pid, [sys.argv[2]], watcher)
    os._exit(0)
watcher.close()
if sys.argv[3] != 'closed_before_ready':
    assert parent.recv(1) == b'A'
    if sys.argv[3]:
        parent.sendall(sys.argv[3].encode())
parent.close()
time.sleep(.2)
assert os.waitpid(child, os.WNOHANG) == (0, 0), 'watcher exited while parent lives'
assert os.path.isdir(sys.argv[2]), 'control failure removed a live runtime'
"""
    result = subprocess.run(
        [sys.executable, "-c", driver, path, str(runtime), message],
        capture_output=True,
        text=True,
        timeout=10,
        check=False,
    )
    assert result.returncode == 0, result.stderr
    deadline = time.monotonic() + 10
    while runtime.exists():
        assert time.monotonic() < deadline, "watcher did not clean after parent exit"
        time.sleep(0.01)


@pytest.mark.parametrize("phase", ["early", "arming", "ready"])
def test_real_parent_exits_before_or_after_readiness(helper, tmp_path, phase):
    path, _ = helper
    runtime = tmp_path / "runtime"
    runtime.mkdir()
    child = """
import os, runpy, sys, time
path, parent, runtime, phase = sys.argv[1:]
support = runpy.run_path(path)
if phase == 'arming':
    original = support['main'].__globals__['_arm_watch']
    def arm(pid, resources):
        open(runtime + '/arming', 'w').close()
        time.sleep(.2)
        return original(pid, resources)
    support['main'].__globals__['_arm_watch'] = arm
sys.argv = [path, parent, runtime]
sys.exit(support['main']())
"""
    driver = """
import os, subprocess, sys, time
child = subprocess.Popen([
    sys.executable, '-I', '-S', '-c', sys.argv[1], sys.argv[2], str(os.getpid()), *sys.argv[3:]
])
if sys.argv[4] == 'ready':
    assert child.wait(timeout=10) == 0
    assert os.path.isdir(sys.argv[3])
elif sys.argv[4] == 'arming':
    deadline = time.monotonic() + 10
    while not os.path.isfile(sys.argv[3] + '/arming'):
        assert time.monotonic() < deadline
        time.sleep(.01)
sys.exit(17)
"""
    result = subprocess.run(
        [sys.executable, "-c", driver, child, path, str(runtime), phase],
        capture_output=True,
        text=True,
        timeout=10,
        check=False,
    )
    assert result.returncode == 17, result.stderr
    deadline = time.monotonic() + 10
    while runtime.exists():
        assert time.monotonic() < deadline, "orphaned helper did not remove runtime"
        time.sleep(0.01)


@pytest.mark.parametrize("closed_fds", ["", "0", "2", "0,2"])
@pytest.mark.parametrize("fallback", [False, True])
def test_closed_stdio_and_descriptor_above_soft_limit(
    helper, tmp_path, closed_fds, fallback
):
    path, _ = helper
    runtime = tmp_path / "runtime"
    runtime.mkdir()
    child = """
import os, resource, runpy, select, sys
path, parent, runtime, closed_fds, fallback = sys.argv[1:]
resource.setrlimit(resource.RLIMIT_NOFILE, (64, resource.getrlimit(resource.RLIMIT_NOFILE)[1]))
for fd in closed_fds.split(','):
    if fd:
        os.close(int(fd))
if fallback == 'True':
    for module, name in ((os, 'pidfd_open'), (select, 'kqueue')):
        if hasattr(module, name):
            delattr(module, name)
sys.argv = [path, parent, runtime]
runpy.run_path(path, run_name='__main__')
"""
    driver = """
import os, select, subprocess, sys
read_fd, write_fd = os.pipe()
os.dup2(write_fd, 200)
os.close(write_fd)
child = subprocess.Popen(
    [sys.executable, '-I', '-S', '-c', sys.argv[1], sys.argv[2], str(os.getpid()), *sys.argv[3:]],
    pass_fds=(200,), stdout=subprocess.PIPE,
)
os.close(200)
assert child.wait(timeout=10) == 0, 'helper failed to arm the watcher'
assert select.select([read_fd], [], [], 5)[0], 'helper retained fd200 above its soft limit'
assert os.read(read_fd, 1) == b''
assert os.path.isdir(sys.argv[3]), 'live parent lost its runtime'
"""
    result = subprocess.run(
        [
            sys.executable,
            "-c",
            driver,
            child,
            path,
            str(runtime),
            closed_fds,
            str(fallback),
        ],
        capture_output=True,
        text=True,
        timeout=15,
        check=False,
    )
    assert result.returncode == 0, result.stderr
    deadline = time.monotonic() + 10
    while runtime.exists():
        assert time.monotonic() < deadline, "runtime leaked with closed descriptors"
        time.sleep(0.01)


@pytest.mark.skipif(sys.platform != "linux", reason="Linux subreaper contract")
def test_subreaper_adopts_watcher_until_application_exit(helper, tmp_path):
    path, _ = helper
    runtime = tmp_path / "runtime"
    runtime.mkdir()
    driver = """
import ctypes, os, subprocess, sys
libc = ctypes.CDLL(None, use_errno=True)
assert libc.prctl(36, 1, 0, 0, 0) == 0  # PR_SET_CHILD_SUBREAPER
subprocess.run([sys.executable, '-I', '-S', sys.argv[1], str(os.getpid()), sys.argv[2]], check=True)
# The direct helper has exited, but a subreaper adopts its live watcher. A
# blocking wait-for-all would deadlock; users need persistent roots here.
assert os.waitpid(-1, os.WNOHANG) == (0, 0)
assert os.path.isdir(sys.argv[2])
"""
    result = subprocess.run(
        [sys.executable, "-c", driver, path, str(runtime)],
        capture_output=True,
        text=True,
        timeout=10,
    )
    assert result.returncode == 0, result.stderr
    deadline = time.monotonic() + 10
    while runtime.exists():
        assert time.monotonic() < deadline, "watcher did not clean after subreaper exit"
        time.sleep(0.01)
