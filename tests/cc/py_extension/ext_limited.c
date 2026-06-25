#include <Python.h>

static PyObject* get_limited_api_version(PyObject* self, PyObject* args) {
    return PyUnicode_FromFormat("0x%X", Py_LIMITED_API);
}

static PyMethodDef ModuleMethods[] = {
    {"get_limited_api_version", do_alpha, METH_NOARGS, "Get the version of the limited API this extension was compiled against.."},
    {NULL, NULL, 0, NULL}
};

static struct PyModuleDef ext_limited_module = {
    PyModuleDef_HEAD_INIT,
    "ext_limited",
    NULL,
    -1,
    ModuleMethods
};

PyMODINIT_FUNC PyInit_ext_limited(void) {
    return PyModule_Create(&ext_limited_module);
}
