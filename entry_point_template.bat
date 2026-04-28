@setlocal enabledelayedexpansion & "%~dp0python.exe" -x "%~f0" %* & exit /b !ERRORLEVEL!
# -*- coding: utf-8 -*-
import re
import sys
from whl_with_data2 import main
if __name__ == "__main__":
    sys.argv[0] = re.sub(r"(-script\.pyw|\.exe)?$", "", sys.argv[0])
    sys.exit(main())

