@echo off
SETLOCAL ENABLEEXTENSIONS
SETLOCAL ENABLEDELAYEDEXPANSION

rem --- begin runfiles resolution ---
set "MF=%RUNFILES_MANIFEST_FILE:/=\%"
set "TARGET_FILE=%target_file%"

set "MAIN_BIN="
if defined MF (
  if exist "%MF%" (
    for /F "tokens=1* usebackq" %%a in (`findstr.exe /l /c:"!TARGET_FILE! " "%MF%"`) do (
      set "MAIN_BIN=%%b"
    )
  )
)
if "!MAIN_BIN!" equ "" (
  set "TF_WIN=!TARGET_FILE:/=\!"
  if "%RUNFILES_MANIFEST_ONLY%" neq "1" if defined RUNFILES_DIR (
    if exist "%RUNFILES_DIR%\!TF_WIN!" (
      set "MAIN_BIN=%RUNFILES_DIR%\!TF_WIN!"
    )
  )
  if "!MAIN_BIN!" equ "" (
    if exist "!TF_WIN!" (
      set "MAIN_BIN=!TF_WIN!"
    )
  )
)

if "!MAIN_BIN!" equ "" (
  echo>&2 ERROR: interpreter executable not found: !TARGET_FILE!
  exit /b 1
)

set "MAIN_BIN=!MAIN_BIN:/=\!"

if not defined PYTHONHOME (
  for %%d in ("!MAIN_BIN!") do set "PYTHONHOME=%%~dpd"
  if "!PYTHONHOME:~-1!"=="\" set "PYTHONHOME=!PYTHONHOME:~0,-1!"
)

"!MAIN_BIN!" %*
exit /b !ERRORLEVEL!
