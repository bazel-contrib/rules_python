#include <Python.h>

static PyObject* get_magic_number(PyObject* self, PyObject* args) {
    return PyLong_FromLong(42);
}

static PyMethodDef ModuleMethods[] = {
    {"get_magic_number", get_magic_number, METH_NOARGS, "Returns 42."},
    {NULL, NULL, 0, NULL}
};

static struct PyModuleDef ext_pkg_test_module = {
    PyModuleDef_HEAD_INIT,
    "ext_pkg_test",
    NULL,
    -1,
    ModuleMethods
};

PyMODINIT_FUNC PyInit_ext_pkg_test(void) {
    return PyModule_Create(&ext_pkg_test_module);
}
