#include <Python.h>

// The headers must be the ones of the debug runtime.
#ifndef Py_DEBUG
#error "Py_DEBUG is not defined"
#endif

static PyObject* answer(PyObject* self, PyObject* args) {
    return PyLong_FromLong(42);
}

static PyMethodDef methods[] = {
    {"answer", answer, METH_NOARGS, NULL},
    {NULL, NULL, 0, NULL},
};

static struct PyModuleDef module = {
    PyModuleDef_HEAD_INIT, "debug_ext", NULL, -1, methods,
};

PyMODINIT_FUNC PyInit_debug_ext(void) {
    return PyModule_Create(&module);
}
