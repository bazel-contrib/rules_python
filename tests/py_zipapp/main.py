"A trivial zipapp that prints a message or waits for a signal."

import os
import signal
import sys


def wait_for_signal(handle_signal):
    if handle_signal:

        def handle(signum, _frame):
            print(f"received:{signum}", flush=True)

        signal.signal(signal.SIGTERM, handle)

    print(f"ready:{os.getpid()}", flush=True)
    signal.pause()
    return 0


def main():
    if sys.argv[1:] == ["wait-for-sigterm"]:
        return wait_for_signal(handle_signal=True)
    if sys.argv[1:] == ["wait-for-unhandled-sigterm"]:
        return wait_for_signal(handle_signal=False)
    if len(sys.argv) == 3 and sys.argv[1] == "exit":
        return int(sys.argv[2])

    print("Hello from zipapp")
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
