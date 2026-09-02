@echo off
if not defined BUILD_WORKSPACE_DIRECTORY goto :build

set "out=%BUILD_WORKSPACE_DIRECTORY%\{{src_out}}"
"{{args}}" --output-file "%out%" %*
exit /b %ERRORLEVEL%

:build
set "out={{out}}"
if exist "{{src_out}}" copy /Y "{{src_out}}" "%out%" >nul
"{{args}}"
exit /b %ERRORLEVEL%
