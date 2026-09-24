"""An isolated native console for observing Windows application handoff."""

import ctypes
import os
import signal
import subprocess
import sys
import threading
import time
from pathlib import Path


def wait_for(predicate):
    deadline = time.monotonic() + 10
    while not predicate():
        if time.monotonic() >= deadline:
            raise AssertionError("console fixture did not reach its barrier")
        time.sleep(0.01)


def application(root, mode, workspace):
    if mode == "high_bit":
        ctypes.windll.kernel32.ExitProcess(0xC000013A)
    count = 0

    def interrupted(_signum, _frame):
        nonlocal count
        count += 1
        (root / "interrupts").write_text(str(count))
        if mode == "handled":
            raise SystemExit(23)

    if mode != "inherited_ignore":
        signal.signal(signal.SIGINT, interrupted)
    try:
        (root / "ready").touch()
        wait_for(lambda: (root / "release").exists())
        return 17 if mode == "ignored" else 29
    finally:
        (root / "stopping").touch()
        wait_for(lambda: (root / "release").exists())
        assert workspace.is_dir(), "workspace removed before application finally"
        (root / "finished").touch()


def controller(root, mode):
    from python.private._rules_python_bootstrap import model, process, storage

    # Test runners may inherit an ignored console; establish this fixture's
    # disposition explicitly before creating its application child.
    assert ctypes.windll.kernel32.SetConsoleCtrlHandler(
        None, mode == "inherited_ignore"
    )
    if mode == "inherited_ignore":
        signal.signal(signal.SIGINT, signal.SIG_IGN)
    else:
        signal.signal(signal.SIGINT, signal.default_int_handler)
    waiting = threading.Event()
    children = []
    failures = []
    original_popen = subprocess.Popen

    def spawn(*args, **kwargs):
        child = original_popen(*args, **kwargs)
        children.append(child)
        original_wait = child.wait

        def wait(*args, **kwargs):
            # This barrier is after execute's registration-time cancellation
            # check. Child readiness alone does not establish that handoff.
            waiting.set()
            return original_wait(*args, **kwargs)

        child.wait = wait
        return child

    subprocess.Popen = spawn
    with process.Cancellation() as cancellation, storage.Workspace(
        directory=root
    ) as workspace:
        owned = Path(workspace.allocate())
        (root / "workspace").write_text(str(owned))

        def interrupt():
            try:
                assert waiting.wait(10), "parent never entered child wait"
                wait_for(lambda: (root / "ready").exists())
                # Broadcast only within this fixture's CREATE_NEW_CONSOLE.
                # CTRL_C_EVENT cannot be scoped to a nonzero process-group ID.
                assert ctypes.windll.kernel32.GenerateConsoleCtrlEvent(0, 0)
                if mode == "handled":
                    wait_for(lambda: (root / "stopping").exists())
                elif mode == "ignored":
                    wait_for(lambda: (root / "interrupts").exists())
                time.sleep(0.2)
                assert children[0].poll() is None, "parent killed application cleanup"
                assert owned.is_dir(), "parent removed live application workspace"
                if mode != "inherited_ignore":
                    assert (root / "interrupts").read_text() == "1"
                else:
                    assert not (root / "interrupts").exists()
            except BaseException as error:
                failures.append(error)
            finally:
                (root / "release").touch()

        thread = threading.Thread(target=interrupt) if mode != "high_bit" else None
        if thread is not None:
            thread.start()
        command = model.Invocation(
            sys.executable,
            (sys.executable, __file__, "application", str(root), mode, str(owned)),
            dict(os.environ),
            None,
        )
        try:
            status = process.execute(command, workspace, "unused", cancellation)
        finally:
            if thread is not None:
                thread.join(12)
                assert not thread.is_alive(), "console controller did not finish"
        if failures:
            raise failures[0]
    assert not owned.exists(), "workspace survived application exit"
    if mode != "high_bit":
        assert (root / "finished").exists()
    return status


if __name__ == "__main__":
    role, directory, mode = sys.argv[1:4]
    root = Path(directory)
    if role == "application":
        sys.exit(application(root, mode, Path(sys.argv[4])))
    sys.exit(controller(root, mode))
