@echo off
if defined BUILD_WORKSPACE_DIRECTORY (
    set "out=%BUILD_WORKSPACE_DIRECTORY%\{{src_out}}"
) else (
    exit /b 1
)

for %%f in ("%out%") do set "project_dir=%%~dpf"
set "project_dir=%project_dir:~0,-1%"
"{{args}}" --directory "%project_dir%" %*
copy "%project_dir%\uv.lock" "%out%"
