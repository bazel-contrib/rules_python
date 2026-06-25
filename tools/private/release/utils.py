"""Utility functions for the release tool."""

import subprocess


def run_cmd(*args, check=True, capture_output=True):
    """Runs a command as a subprocess with separate arguments (prints command).

    If the command fails, it raises the CalledProcessError after attaching
    a detailed note explaining the failure to preserve the stack trace.
    """
    cmd = [str(arg) for arg in args]
    print(f"Running: {' '.join(cmd)}")
    try:
        result = subprocess.run(
            cmd,
            check=check,
            stdout=subprocess.PIPE if capture_output else None,
            stderr=subprocess.PIPE if capture_output else None,
            universal_newlines=True,
        )
        return result.stdout.strip() if capture_output else None
    except subprocess.CalledProcessError as e:
        note = f"Error running command: {' '.join(cmd)}"
        if capture_output:
            note += f"\nStdout: {e.stdout}\nStderr: {e.stderr}"
        e.add_note(note)
        raise
