#include <Python.h>

#include "tests/cc/py_extension/add_one.h"

// A simple function that returns a Python integer.
static PyObject* do_alpha(PyObject* self, PyObject* args) {
    return PyLong_FromLong(add_one(41));
}

// Method definition object for this extension, these are the functions
// that will be available in the module.
static PyMethodDef ModuleMethods[] = {
    {"do_alpha", do_alpha, METH_NOARGS, "A simple C function."},
    {NULL, NULL, 0, NULL}        /* Sentinel */
};

// Module definition
// The arguments of this structure tell Python what to call your extension,
// what its methods are and where to look for its method definitions.
static struct PyModuleDef ext_shared_module = {
    PyModuleDef_HEAD_INIT,
    "ext_shared",   /* name of module */
    NULL, /* module documentation, may be NULL */
    -1,       /* size of per-interpreter state of the module,
                 or -1 if the module keeps state in global variables. */
    ModuleMethods
};

// The module init function. This must be exported and retained in the
// shared library output.
PyMODINIT_FUNC PyInit_ext_shared(void) {
    return PyModule_Create(&ext_shared_module);
}
