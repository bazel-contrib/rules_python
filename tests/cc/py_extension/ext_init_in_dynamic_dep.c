
#include <Python.h>

// No methods defined; we're just testing the init function.
static PyMethodDef ModuleMethods[] = {
    {NULL, NULL, 0, NULL}        /* Sentinel */
};

static struct PyModuleDef ext_init_in_dynamic_dep_module = {
    PyModuleDef_HEAD_INIT,
    "ext_init_in_dynamic_dep",   /* name of module */
    NULL, /* module documentation, may be NULL */
    -1,       /* size of per-interpreter state of the module,
                 or -1 if the module keeps state in global variables. */
    ModuleMethods
};

PyMODINIT_FUNC PyInit_ext_init_in_dynamic_dep(void) {
    return PyModule_Create(&ext_init_in_dynamic_dep_module);
}
