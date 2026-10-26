"""First-party build helper module used to test py_library in py_sdist_wheel.build_deps."""

import os

with open(
    os.path.join(os.path.dirname(__file__), "helper_data.txt"),
    encoding="utf-8",
) as _f:
    HELPER_DATA = _f.read().strip()

HELPER_READY = HELPER_DATA == "helper_data_ok"
