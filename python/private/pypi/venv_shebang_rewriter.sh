#!/bin/sh
set -eu

IN="$1"
OUT="$2"
TARGET_OS="$3"

FIRST_LINE=$(head -n 1 "$IN")

if [ "$TARGET_OS" = "windows" ]; then
  case "$FIRST_LINE" in
    "#!pythonw"*) PYTHON_EXE="pythonw.exe" ;;
    *)            PYTHON_EXE="python.exe" ;;
  esac
  # A Batch-Python polyglot. Batch executes the first line and exits,
  # while Python (via -x) ignores the first line and executes the rest.
  echo "@setlocal enabledelayedexpansion & \"%~dp0$PYTHON_EXE\" -x \"%~f0\" %* & exit /b !ERRORLEVEL!" > "$OUT"
else
  echo "#!/bin/sh" > "$OUT"
  # A Shell-Python polyglot. The shell executes the triple-quoted 'exec'
  # command, re-running the script with python3 from the scripts directory.
  # Python ignores the triple-quoted string and continues.
  echo "'''exec' \"\$(dirname \"\$0\")/python3\" \"\$0\" \"\$@\"" >> "$OUT"
  echo "' '''" >> "$OUT"
fi

tail -n +2 "$IN" >> "$OUT"
chmod +x "$OUT"
