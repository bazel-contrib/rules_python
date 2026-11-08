@echo off
if not defined BUILD_WORKSPACE_DIRECTORY goto :not_in_workspace
rem `uv lock` always reads and writes `uv.lock` in the project directory
rem (`{{project_lock}}` relative to `cd`). Stage `_main` into a writable
rem temporary directory so the runfiles directory is not modified.
set "out=%BUILD_WORKSPACE_DIRECTORY%\{{src_out}}"
set "orig_dir=%CD%"
for %%i in ("%CD%\..") do set "runfiles_dir=%%~fi"
set "tmp_dir=%TEMP%\uv_lock_%RANDOM%_%RANDOM%"
mkdir "%tmp_dir%" >nul 2>&1
for /d %%d in ("%runfiles_dir%\*") do (
    if /i not "%%~nxd"=="_main" mklink /J "%tmp_dir%\%%~nxd" "%%~fd" >nul
)
xcopy /E /I /Q /Y "%orig_dir%" "%tmp_dir%\_main" >nul
pushd "%tmp_dir%\_main"
if exist "%out%" (
    for %%d in ("{{project_lock}}") do mkdir "%%~dpd" >nul 2>&1
    copy /y "%out%" "{{project_lock}}" >nul
) else (
    if exist "{{project_lock}}" del /f /q "{{project_lock}}" >nul
)
"{{args}}" %*
set "exit_code=%ERRORLEVEL%"
if %exit_code% equ 0 if exist "{{project_lock}}" (
    for %%d in ("%out%") do mkdir "%%~dpd" >nul 2>&1
    copy /y "{{project_lock}}" "%out%" >nul
)
popd
rmdir /s /q "%tmp_dir%" >nul 2>&1
exit /b %exit_code%

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
