"""Helper to generate deterministic test sdist tar.gz files for py_sdist_wheel tests."""

from __future__ import annotations

import argparse
import io
import pathlib
import tarfile

_CEXT_SOURCE = """\
#define PY_SSIZE_T_CLEAN
#include <Python.h>

static PyObject* cext_add_ints(PyObject* self, PyObject* args) {
    long a = 0, b = 0;
    if (!PyArg_ParseTuple(args, "ll", &a, &b)) return NULL;
    return PyLong_FromLong(a + b);
}

static PyMethodDef CextMethods[] = {
    {"add_ints", cext_add_ints, METH_VARARGS, "Add two ints."},
    {NULL, NULL, 0, NULL}
};

static struct PyModuleDef cextmodule = {
    PyModuleDef_HEAD_INIT, "cext_demo", NULL, -1, CextMethods
};

PyMODINIT_FUNC PyInit_cext_demo(void) {
    return PyModule_Create(&cextmodule);
}
"""


def write_sdist_tar(out: pathlib.Path, files: dict[str, str]) -> pathlib.Path:
    out.parent.mkdir(parents=True, exist_ok=True)
    with tarfile.open(out, "w:gz") as tf:
        for name, content in files.items():
            data = content.encode("utf-8")
            info = tarfile.TarInfo(name=name)
            info.size = len(data)
            info.mtime = 315532800
            info.mode = 0o644
            tf.addfile(info, io.BytesIO(data))
    return out


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("out", type=pathlib.Path)
    parser.add_argument("--c-ext", action="store_true")
    args = parser.parse_args()

    if args.c_ext:
        write_sdist_tar(
            args.out,
            {
                "sdist_cext-0.1.0/PKG-INFO": "Metadata-Version: 2.1\nName: sdist-cext\nVersion: 0.1.0\n",
                "sdist_cext-0.1.0/setup.py": (
                    "from setuptools import Extension, setup\n"
                    "setup(name='sdist-cext', version='0.1.0', packages=['sdist_cext'], "
                    "ext_modules=[Extension('cext_demo', ['src/cext_demo.c'])])\n"
                ),
                "sdist_cext-0.1.0/sdist_cext/__init__.py": "import cext_demo\nadd_ints = cext_demo.add_ints\n",
                "sdist_cext-0.1.0/src/cext_demo.c": _CEXT_SOURCE,
            },
        )
    else:
        write_sdist_tar(
            args.out,
            {
                "sdist_demo-0.5.0/pyproject.toml": (
                    "[build-system]\n"
                    'requires = ["setuptools", "wheel", "demo-pkg>=1.0", "classic-bdep>=1.0"]\n'
                    'build-backend = "setuptools.build_meta"\n'
                ),
                "sdist_demo-0.5.0/PKG-INFO": "Metadata-Version: 2.1\nName: sdist-demo\nVersion: 0.5.0\n",
                "sdist_demo-0.5.0/setup.py": (
                    "import classic_bdep, demo_pkg, helper_mod, packaging, packaging.version\n"
                    "from setuptools import setup\n"
                    "assert classic_bdep.CLASSIC_BDEP_OK is True\n"
                    "assert demo_pkg.VALUE == 'patched_in_action'\n"
                    "assert helper_mod.HELPER_READY is True\n"
                    "assert helper_mod.HELPER_DATA == 'helper_data_ok'\n"
                    "assert not hasattr(packaging, 'SHADOW_MARKER')\n"
                    "setup(name='sdist-demo', version='0.5.0', packages=['sdist_demo'])\n"
                ),
                "sdist_demo-0.5.0/sdist_demo/__init__.py": 'GREETING = "unpatched_sdist"\n',
            },
        )


if __name__ == "__main__":
    main()
