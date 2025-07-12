"""
A shim to get `main_module` working with `bootstrap_impl=system_python`.
"""

import os
import runpy

if __name__ == "__main__":
    runpy.run_module("%main_module%", run_name="__main__", alter_sys=True)
