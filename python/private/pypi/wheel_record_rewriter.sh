#!/bin/sh
set -eu

IN="$1"
OUT="$2"
TARGET_OS="$3"
DATA_DIR_BASENAME="$4"

DATA_PREFIX="${DATA_DIR_BASENAME}/"
QUOTED_DATA_PREFIX="\"${DATA_DIR_BASENAME}/"

if [ "$TARGET_OS" = "windows" ]; then
  DATA_REPL="../../"
  HEADERS_REPL="../../Include/"
  PLATLIB_REPL=""
  PURELIB_REPL=""
  SCRIPTS_REPL="../../Scripts/"
else
  DATA_REPL="../../../"
  HEADERS_REPL="../../../include/"
  PLATLIB_REPL=""
  PURELIB_REPL=""
  SCRIPTS_REPL="../../../bin/"
fi

awk -v data_prefix="$DATA_PREFIX" \
    -v quoted_data_prefix="$QUOTED_DATA_PREFIX" \
    -v data_repl="$DATA_REPL" \
    -v headers_repl="$HEADERS_REPL" \
    -v platlib_repl="$PLATLIB_REPL" \
    -v purelib_repl="$PURELIB_REPL" \
    -v scripts_repl="$SCRIPTS_REPL" \
    -v target_os="$TARGET_OS" '
{
  line = $0
  quote = ""
  if (substr(line, 1, length(quoted_data_prefix)) == quoted_data_prefix) {
    quote = "\""
    rest = substr(line, length(quoted_data_prefix) + 1)
  } else if (substr(line, 1, length(data_prefix)) == data_prefix) {
    rest = substr(line, length(data_prefix) + 1)
  } else {
    print line
    next
  }

  if (substr(rest, 1, 8) == "purelib/") {
    print quote purelib_repl substr(rest, 9)
  } else if (substr(rest, 1, 8) == "platlib/") {
    print quote platlib_repl substr(rest, 9)
  } else if (substr(rest, 1, 8) == "scripts/") {
    entry = substr(rest, 9)
    if (target_os == "windows") {
      if (quote == "\"") {
        idx = index(entry, "\"")
        spath = substr(entry, 1, idx - 1)
        suffix = substr(entry, idx)
      } else {
        idx = index(entry, ",")
        spath = substr(entry, 1, idx - 1)
        suffix = substr(entry, idx)
      }
      bname = spath
      n = split(spath, parts, "/")
      if (n > 0) {
        bname = parts[n]
      }
      if (index(bname, ".") == 0) {
        spath = spath ".bat"
      }
      print quote scripts_repl spath suffix
    } else {
      print quote scripts_repl entry
    }
  } else if (substr(rest, 1, 8) == "headers/") {
    print quote headers_repl substr(rest, 9)
  } else if (substr(rest, 1, 5) == "data/") {
    print quote data_repl substr(rest, 6)
  } else {
    print line
  }
}
' "$IN" > "$OUT"
