"""Generates a deterministic tiny meson-python C/C++ sdist tar.gz for testing."""

from __future__ import annotations

import argparse
import io
import pathlib
import tarfile

_PYPROJECT_TOML = """\
[build-system]
build-backend = "mesonpy"
requires = ["meson-python"]

[project]
name = "tiny-meson"
version = "0.1.0"
requires-python = ">=3.9"
"""

_MESON_BUILD = """\
project(
  'tiny-meson',
  'c',
  'cpp',
  version: '0.1.0',
  default_options: ['cpp_std=c++17'],
)

py = import('python').find_installation(pure: false)

py.install_sources(
  'tiny_meson/__init__.py',
  subdir: 'tiny_meson',
)

py.extension_module(
  '_tiny_c',
  'tiny_meson/_tiny_c.c',
  subdir: 'tiny_meson',
  install: true,
)

py.extension_module(
  '_tiny_cpp',
  'tiny_meson/_tiny_cpp.cpp',
  subdir: 'tiny_meson',
  install: true,
)
"""

_INIT_PY = """\
from tiny_meson._tiny_c import add_ints
from tiny_meson._tiny_cpp import mul_ints

__all__ = ["add_ints", "mul_ints"]
"""

_TINY_C = """\
#define PY_SSIZE_T_CLEAN
#include <Python.h>

static PyObject *tiny_add_ints(PyObject *self, PyObject *args) {
    long a = 0, b = 0;
    if (!PyArg_ParseTuple(args, "ll", &a, &b)) {
        return NULL;
    }
    return PyLong_FromLong(a + b);
}

static PyMethodDef TinyCMethods[] = {
    {"add_ints", tiny_add_ints, METH_VARARGS, "Add two integers in C."},
    {NULL, NULL, 0, NULL},
};

static struct PyModuleDef tiny_c_module = {
    PyModuleDef_HEAD_INIT,
    "_tiny_c",
    NULL,
    -1,
    TinyCMethods,
};

PyMODINIT_FUNC PyInit__tiny_c(void) {
    return PyModule_Create(&tiny_c_module);
}
"""

_TINY_CPP = """\
#define PY_SSIZE_T_CLEAN
#include <Python.h>
#include <vector>

namespace {

long multiply_pair(long a, long b) {
    std::vector<long> vals = {a, b};
    return vals[0] * vals[1];
}

PyObject *tiny_mul_ints(PyObject *self, PyObject *args) {
    long a = 0, b = 0;
    if (!PyArg_ParseTuple(args, "ll", &a, &b)) {
        return nullptr;
    }
    return PyLong_FromLong(multiply_pair(a, b));
}

PyMethodDef TinyCppMethods[] = {
    {"mul_ints", tiny_mul_ints, METH_VARARGS, "Multiply two integers in C++."},
    {nullptr, nullptr, 0, nullptr},
};

PyModuleDef tiny_cpp_module = {
    PyModuleDef_HEAD_INIT,
    "_tiny_cpp",
    nullptr,
    -1,
    TinyCppMethods,
};

}  // namespace

PyMODINIT_FUNC PyInit__tiny_cpp(void) {
    return PyModule_Create(&tiny_cpp_module);
}
"""


def write_sdist_tar(out: pathlib.Path, files: dict[str, str]) -> None:
    out.parent.mkdir(parents=True, exist_ok=True)
    with tarfile.open(out, "w:gz") as tf:
        for name, content in files.items():
            data = content.encode("utf-8")
            info = tarfile.TarInfo(name=name)
            info.size = len(data)
            info.mtime = 315532800
            info.mode = 0o644
            tf.addfile(info, io.BytesIO(data))


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("out", type=pathlib.Path)
    args = parser.parse_args()

    write_sdist_tar(
        args.out,
        {
            "tiny_meson-0.1.0/pyproject.toml": _PYPROJECT_TOML,
            "tiny_meson-0.1.0/meson.build": _MESON_BUILD,
            "tiny_meson-0.1.0/tiny_meson/__init__.py": _INIT_PY,
            "tiny_meson-0.1.0/tiny_meson/_tiny_c.c": _TINY_C,
            "tiny_meson-0.1.0/tiny_meson/_tiny_cpp.cpp": _TINY_CPP,
        },
    )


if __name__ == "__main__":
    main()
