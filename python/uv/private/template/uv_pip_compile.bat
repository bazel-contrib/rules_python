@echo off
if not defined BUILD_WORKSPACE_DIRECTORY goto :build

set "out=%BUILD_WORKSPACE_DIRECTORY%\{{src_out}}"
"{{args}}" --output-file "%out%" %*
exit /b %ERRORLEVEL%

:build
set "out={{out}}"
if exist "{{src_out}}" copy /Y "{{src_out}}" "%out%" >nul
set "__srcs="$SRCS""
if defined __srcs (
    for %%s in (%__srcs%) do (
        for %%d in ("{{rootdir}}\%%s") do mkdir "%%~dpd" >nul 2>&1
        copy /Y "%%s" "{{rootdir}}\%%s" >nul
    )
)
"{{args}}"
exit /b %ERRORLEVEL%