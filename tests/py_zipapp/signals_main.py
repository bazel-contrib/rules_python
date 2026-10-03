"A zipapp that reports its PID and extraction directory, then waits for SIGTERM."

import os
import signal
import sys
import time


def main():
    if len(sys.argv) > 1 and sys.argv[1].startswith("--exit-code="):
        sys.exit(int(sys.argv[1].split("=", 1)[1]))

    def on_sigterm(signum, frame):
        # print() isn't reentrant; the signal may arrive while main() prints.
        os.write(sys.stdout.fileno(), b"got SIGTERM\n")
        sys.exit(0)

    signal.signal(signal.SIGTERM, on_sigterm)
    print(f"pid={os.getpid()}", flush=True)
    print(f"zip_dir={sys._xoptions.get('RULES_PYTHON_ZIP_DIR', '')}", flush=True)
    while True:
        time.sleep(60)


if __name__ == "__main__":
    main()
