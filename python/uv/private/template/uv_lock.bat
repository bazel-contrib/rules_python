@echo off
if not defined BUILD_WORKSPACE_DIRECTORY goto :not_in_workspace
"{{args}}" %*
exit /b %ERRORLEVEL%

:not_in_workspace
if exist "{{src_out}}" copy /y "{{src_out}}" "{{out}}" >nul
if exist "{{out}}" (
    for %%d in ("{{project_lock}}") do mkdir "%%~dpd" >nul 2>&1
    copy /y "{{out}}" "{{project_lock}}" >nul
)
"{{args}}" %*
set "exit_code=%ERRORLEVEL%"
if exist "{{project_lock}}" copy /y "{{project_lock}}" "{{out}}" >nul
exit /b %exit_code%