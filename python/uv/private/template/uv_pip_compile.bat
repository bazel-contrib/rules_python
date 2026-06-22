@echo off
if not defined BUILD_WORKSPACE_DIRECTORY goto :else
set "out=%BUILD_WORKSPACE_DIRECTORY%\{{src_out}}"
"{{args}}" --output-file "%out%" %*
exit /b %ERRORLEVEL%

:else
"{{args}}" %*
