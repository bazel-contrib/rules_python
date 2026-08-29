#include <Python.h>

static PyObject* get_magic_number(PyObject* self, PyObject* args) {
    return PyLong_FromLong(42);
}

static PyMethodDef ModuleMethods[] = {
    {"get_magic_number", get_magic_number, METH_NOARGS, "Returns 42."},
    {NULL, NULL, 0, NULL}
};

static struct PyModuleDef ext_long_path_module = {
    PyModuleDef_HEAD_INIT,
    "ext_long_path",
    NULL,
    -1,
    ModuleMethods
};

PyMODINIT_FUNC PyInit_ext_long_path(void) {
    return PyModule_Create(&ext_long_path_module);
}
