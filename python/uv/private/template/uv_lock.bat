@echo off
if not defined BUILD_WORKSPACE_DIRECTORY goto :not_in_workspace
"{{args}}" %*
exit /b %ERRORLEVEL%

:not_in_workspace

if not exist "{{src_out}}" goto :no_src_out
copy /y "{{src_out}}" "{{out}}"
del /f "{{src_out}}"
copy /y "{{out}}" "{{src_out}}"
"{{args}}" %*
set "exit_code=%ERRORLEVEL%"
copy /y "{{src_out}}" "{{out}}"
exit /b %exit_code%

:no_src_out
"{{args}}" %*
set "exit_code=%ERRORLEVEL%"
copy /y "{{src_out}}" "{{out}}"
exit /b %exit_code%