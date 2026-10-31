"""Verifies execution of a py_interpreter_program target with sibling srcs."""

from __future__ import annotations

import os
import unittest
from pathlib import Path


class RunInterpreterProgramTest(unittest.TestCase):
    def test_sibling_import_and_no_bytecode(self) -> None:
        out_path = Path(os.environ["PROG_OUTPUT"])
        self.assertEqual(
            out_path.read_text(encoding="utf-8").strip(), "ok-from-sibling"
        )


if __name__ == "__main__":
    unittest.main()
