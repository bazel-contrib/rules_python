@echo off
if defined BUILD_WORKSPACE_DIRECTORY (
    "{{args}}" %*
    exit /b %ERRORLEVEL%
)

if exist "{{src_out}}" (
    copy /y "{{src_out}}" "{{out}}"
    del /f "{{src_out}}"
    copy /y "{{out}}" "{{src_out}}"
    "{{args}}" %*
    copy /y "{{src_out}}" "{{out}}"
) else (
    "{{args}}" %*
    copy /y "{{src_out}}" "{{out}}"
)