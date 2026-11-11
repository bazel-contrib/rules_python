"""Runtime test verifying merged TreeArtifact-backed venv site-packages."""

from __future__ import annotations

import importlib
import os
import sys
from pathlib import Path


def _assert_in_venv(mod_file: str | None, mod_name: str) -> None:
    assert mod_file is not None, f"Expected __file__ on {mod_name}"
    actual = str(Path(mod_file)).lower() if os.name == "nt" else mod_file
    prefix = str(Path(sys.prefix)).lower() if os.name == "nt" else sys.prefix
    assert actual.startswith(prefix), (
        f"{mod_name} ({mod_file}) was not loaded from venv ({sys.prefix})"
    )


def test_imports_from_merged_tree_artifacts() -> None:
    assert sys.prefix != sys.base_prefix, "Expected to run inside a venv"

    foo = importlib.import_module("foo")
    foo_a = importlib.import_module("foo.a")
    foo_b = importlib.import_module("foo.plugins.b")
    foo_shared = importlib.import_module("foo.plugins.shared")
    ns_one = importlib.import_module("pkgutil_ns.one")
    ns_two = importlib.import_module("pkgutil_ns.two")

    assert foo.ORIGIN == "tree_a"
    assert foo_a.VALUE == "from_a"
    assert foo_b.VALUE == "from_b"
    assert foo_shared.WINNER == "tree_a"
    assert ns_one.VALUE == 1
    assert ns_two.VALUE == 2

    for mod in (foo, foo_a, foo_b, foo_shared, ns_one, ns_two):
        _assert_in_venv(mod.__file__, mod.__name__)
