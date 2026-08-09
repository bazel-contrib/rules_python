
#include <Python.h>


static PyObject* calc_one_plus_two(PyObject* self, PyObject* args) {
    return PyLong_FromLong(1 + 2);
}


// Method definition object for this extension, these are the functions
// that will be available in the module.
static PyMethodDef ModuleMethods[] = {
    {"calc_one_plus_two", calc_one_plus_two, METH_NOARGS, "A simple C function."},
    {NULL, NULL, 0, NULL}        /* Sentinel */
};

// Module definition
// The arguments of this structure tell Python what to call your extension,
// what its methods are and where to look for its method definitions.
static struct PyModuleDef ext_source_module = {
    PyModuleDef_HEAD_INIT,
    "ext_source",   /* name of module */
    NULL, /* module documentation, may be NULL */
    -1,       /* size of per-interpreter state of the module,
                 or -1 if the module keeps state in global variables. */
    ModuleMethods
};

// The module init function. This must be exported and retained in the
// shared library output.
PyMODINIT_FUNC PyInit_ext_source(void) {
    return PyModule_Create(&ext_source_module);
}
