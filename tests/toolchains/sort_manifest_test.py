"""Tests for sort_manifest."""

from __future__ import annotations

from pathlib import Path

from python.private.tools.sort_manifest import sort_manifest
from python.runfiles import runfiles


def test_sort_bzl_manifest(tmp_path: Path):
    manifest_file = tmp_path / "runtimes_manifest.bzl"
    manifest_file.write_text(
        '"""Docstring."""\n\n'
        'MANIFEST_TEXT = """\n'
        "# Header comment\n\n"
        "bbbb  20260414/cpython-3.14.0-x86_64-unknown-linux-gnu.tar.gz\n"
        "aaaa  20260414/cpython-3.13.0-x86_64-unknown-linux-gnu.tar.gz\n"
        '"""\n',
        encoding="utf-8",
    )

    assert sort_manifest(manifest_file) is True
    assert manifest_file.read_text(encoding="utf-8") == (
        '"""Docstring."""\n\n'
        'MANIFEST_TEXT = """\n'
        "# Header comment\n\n"
        "aaaa  20260414/cpython-3.13.0-x86_64-unknown-linux-gnu.tar.gz\n"
        "bbbb  20260414/cpython-3.14.0-x86_64-unknown-linux-gnu.tar.gz\n"
        '"""\n'
    )
    assert sort_manifest(manifest_file) is False


def test_runtimes_manifest_bzl_is_sorted(tmp_path: Path):
    src_manifest = (
        runfiles.CreateOrRaise().root()
        / "rules_python/python/private/runtimes_manifest.bzl"
    )
    manifest_copy = tmp_path / "runtimes_manifest.bzl"
    manifest_copy.write_bytes(src_manifest.read_bytes())

    assert sort_manifest(manifest_copy) is False
