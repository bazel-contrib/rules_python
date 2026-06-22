@echo off
if defined BUILD_WORKSPACE_DIRECTORY (
    set "out=%BUILD_WORKSPACE_DIRECTORY%\{{src_out}}"
    "{{args}}" --output-file "%out%" %*
    exit /b %ERRORLEVEL%
)

"{{args}}" %*
