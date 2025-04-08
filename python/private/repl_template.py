import os
from pathlib import Path


def repl_stub():
    pass  # %REPLACE_WHOLE_LINE_WITH_STUB%


def start_repl():
    # Simulate Python's behavior when a valid startup script is defined by the
    # PYTHONSTARTUP variable. If this file path fails to load, print the error
    # and revert to the default behavior.
    if startup_file := os.getenv("PYTHONSTARTUP"):
        try:
            source_code = Path(startup_file).read_text()
        except Exception as error:
            print(f"{type(error).__name__}: {error}")
        else:
            compiled_code = compile(source_code, filename=startup_file, mode="exec")
            eval(compiled_code, {})

    repl_stub()


if __name__ == "__main__":
    start_repl()
