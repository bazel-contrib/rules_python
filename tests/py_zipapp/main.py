"A trivial zipapp that prints a message or waits for a signal."

import os
import signal
import stat
import sys


def wait_for_signal(handle_signal):
    if handle_signal:

        def handle(signum, _frame):
            print(f"received:{signum}", flush=True)

        signal.signal(signal.SIGTERM, handle)

    print(f"file:{__file__}", flush=True)
    print(f"ready:{os.getpid()}", flush=True)
    signal.pause()
    return 0


def main():
    if sys.argv[1:] == ["readonly-file"]:
        path = os.path.join(os.path.dirname(__file__), "readonly-cleanup-test")
        with open(path, "w") as file:
            file.write("Cleanup must remove read-only extracted files.\n")
        os.chmod(path, stat.S_IREAD)
    if sys.argv[1:] == ["check-ignored-signals"]:
        ignored = all(
            signal.getsignal(sig) == signal.SIG_IGN
            for sig in (signal.SIGHUP, signal.SIGINT, signal.SIGQUIT, signal.SIGTERM)
        )
        print(f"ignored-signals:{ignored}")
        return 0
    if sys.argv[1:] == ["wait-for-sigterm"]:
        return wait_for_signal(handle_signal=True)
    if sys.argv[1:] == ["wait-for-unhandled-sigterm"]:
        return wait_for_signal(handle_signal=False)
    if len(sys.argv) == 3 and sys.argv[1] == "exit":
        return int(sys.argv[2])

    print("Hello from zipapp")
    print(f"file:{__file__}")
    print(f"xoption_zip_dir:{sys._xoptions.get('RULES_PYTHON_ZIP_DIR', 'UNSET')}")
    try:
        import some_dep

        print(f"dep: {some_dep}")

        import pkgdep.pkgmod

        print(f"dep: {pkgdep.pkgmod}")
    except ImportError as e:
        e.add_note(
            "Failed to import a dependency.\n" + "sys.path:\n" + "\n".join(sys.path)
        )
        raise
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
