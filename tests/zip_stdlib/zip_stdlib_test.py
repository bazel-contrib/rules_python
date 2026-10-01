"""Tests that the Python standard library is imported from a zip file."""

import json
import os
import sys
import urllib.parse
import zipimport

import pytest


@pytest.mark.parametrize("mod", [json, urllib.parse])
def test_pure_python_stdlib_loaded_from_zip(mod):
    loader = getattr(mod, "__loader__", None)
    assert isinstance(loader, zipimport.zipimporter), (
        f"{mod.__name__} was loaded by {loader!r}, expected zipimporter"
    )
    assert ".zip" in mod.__file__, (
        f"{mod.__name__}.__file__ does not indicate a zip: {mod.__file__}"
    )


@pytest.mark.parametrize("mod", [json, urllib.parse])
def test_on_disk_stdlib_files_not_present(mod):
    loader = getattr(mod, "__loader__", None)
    assert isinstance(loader, zipimport.zipimporter)
    archive = loader.archive
    lib_dir = os.path.dirname(archive)
    candidates = [
        os.path.join(
            lib_dir,
            f"python{sys.version_info.major}.{sys.version_info.minor}",
            mod.__name__.replace(".", os.sep) + ".py",
        ),
        os.path.join(
            lib_dir,
            f"python{sys.version_info.major}.{sys.version_info.minor}",
            mod.__name__.split(".")[0],
        ),
        os.path.join(
            lib_dir,
            "Lib",
            mod.__name__.replace(".", os.sep) + ".py",
        ),
        os.path.join(
            lib_dir,
            "Lib",
            mod.__name__.split(".")[0],
        ),
    ]
    for candidate in candidates:
        assert not os.path.exists(candidate), (
            f"Expected {candidate} to not exist on disk in runfiles"
        )


def test_json_module_works():
    data = {"hello": "world", "num": 42}
    dumped = json.dumps(data)
    assert json.loads(dumped) == data
