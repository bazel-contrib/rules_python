@setlocal enabledelayedexpansion & "%~dp0{PYTHON_EXE}" -x "%~f0" %* & exit /b !ERRORLEVEL!
# -*- coding: utf-8 -*-
import re
import sys
from {MODULE} import {ATTRIBUTE}
if __name__ == "__main__":
    sys.argv[0] = re.sub(r"(-script\.pyw|\.exe)?$", "", sys.argv[0])
    sys.exit({ATTRIBUTE}())
