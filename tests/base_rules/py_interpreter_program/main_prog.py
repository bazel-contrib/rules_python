"""Entry point used to verify sibling staging in py_interpreter_program."""

from __future__ import annotations

import sys
from pathlib import Path

# Intentionally avoid `.resolve()` so imports come from the staged `<name>_/`
# directory rather than following symlinks back to the source tree.
_STAGE_DIR = Path(__file__).parent
sys.path.insert(0, str(_STAGE_DIR))

import helper_mod  # noqa: E402


def main() -> None:
    out_path = Path(sys.argv[1])
    assert sys.dont_write_bytecode, "Expected -B / PYTHONDONTWRITEBYTECODE=1"
    assert not (_STAGE_DIR / "__pycache__").exists()
    out_path.write_text(helper_mod.VALUE + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
