"""Shell utility functions for the release tool."""

import shlex
import subprocess


def run_cmd(*args, check=True, capture_output=True, cwd=None):
    """Runs a command as a subprocess with separate arguments (prints command).

    If the command fails, it raises the CalledProcessError after attaching
    a detailed note explaining the failure to preserve the stack trace.
    """
    cmd = [str(arg) for arg in args]
    cwd_suffix = f" (cwd: {cwd})" if cwd else ""
    print(f"> {shlex.join(cmd)}{cwd_suffix}")
    try:
        result = subprocess.run(
            cmd,
            check=check,
            stdout=subprocess.PIPE if capture_output else None,
            stderr=subprocess.PIPE if capture_output else None,
            universal_newlines=True,
            cwd=cwd,
        )
        return result.stdout.strip() if capture_output else None
    except subprocess.CalledProcessError as e:
        note = f"Error running command: {shlex.join(cmd)}{cwd_suffix}"
        if capture_output:
            note += f"\nStdout: {e.stdout}\nStderr: {e.stderr}"
        e.add_note(note)
        raise
