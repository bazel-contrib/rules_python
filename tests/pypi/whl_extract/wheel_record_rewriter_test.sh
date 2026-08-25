#!/bin/sh
set -eu

REWRITER="$1"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

run_rewriter() {
  case "$REWRITER" in
    *.ps1)
      in_file="$1"
      out_file="$2"
      platform_type="$3"
      data_dir="$4"
      if command -v cygpath >/dev/null 2>&1; then
        in_file="$(cygpath -w "$in_file")"
        out_file="$(cygpath -w "$out_file")"
      fi
      powershell.exe -ExecutionPolicy Bypass -NoProfile -File "$REWRITER" "$in_file" "$out_file" "$platform_type" "$data_dir"
      ;;
    *)
      "$REWRITER" "$@"
      ;;
  esac
}

INPUT="$TMP_DIR/input_RECORD"
cat <<'EOF' > "$INPUT"
foo-1.0.data/purelib/pkg/__init__.py,sha256=abc,100
foo-1.0.data/purelib/pkg/module.py,sha256=def,200
foo-1.0.data/platlib/pkg/_ext.so,sha256=ghi,300
foo-1.0.data/data/pkg/data.txt,sha256=111,10
foo-1.0.data/headers/pkg/header.h,sha256=222,20
foo-1.0.data/scripts/foo,sha256=444,40
foo-1.0.data/scripts/my_script.sh,sha256=333,30
"foo-1.0.data/purelib/pkg/my file.py",sha256=abc,100
"foo-1.0.data/scripts/my tool",sha256=def,200
"foo-1.0.data/headers/my header.h",sha256=ghi,300
"foo-1.0.data/data/my data.txt",sha256=jkl,400
foo-1.0.data/custom_dir/custom.txt,sha256=xyz,123
top_level/__init__.py,sha256=aaa,50
foo-1.0.dist-info/METADATA,sha256=bbb,60
foo-1.0.dist-info/RECORD,,
EOF

# Test Unix rewrite
UNIX_OUT="$TMP_DIR/unix_RECORD"
run_rewriter "$INPUT" "$UNIX_OUT" "unix" "foo-1.0.data"

EXPECTED_UNIX="$TMP_DIR/expected_unix"
cat <<'EOF' > "$EXPECTED_UNIX"
pkg/__init__.py,sha256=abc,100
pkg/module.py,sha256=def,200
pkg/_ext.so,sha256=ghi,300
../../../pkg/data.txt,sha256=111,10
../../../include/pkg/header.h,sha256=222,20
../../../bin/foo,sha256=444,40
../../../bin/my_script.sh,sha256=333,30
"pkg/my file.py",sha256=abc,100
"../../../bin/my tool",sha256=def,200
"../../../include/my header.h",sha256=ghi,300
"../../../my data.txt",sha256=jkl,400
foo-1.0.data/custom_dir/custom.txt,sha256=xyz,123
top_level/__init__.py,sha256=aaa,50
foo-1.0.dist-info/METADATA,sha256=bbb,60
foo-1.0.dist-info/RECORD,,
EOF

diff -u --strip-trailing-cr "$EXPECTED_UNIX" "$UNIX_OUT"

# Test Windows rewrite
WIN_OUT="$TMP_DIR/win_RECORD"
run_rewriter "$INPUT" "$WIN_OUT" "windows" "foo-1.0.data"

EXPECTED_WIN="$TMP_DIR/expected_win"
cat <<'EOF' > "$EXPECTED_WIN"
pkg/__init__.py,sha256=abc,100
pkg/module.py,sha256=def,200
pkg/_ext.so,sha256=ghi,300
../../pkg/data.txt,sha256=111,10
../../Include/pkg/header.h,sha256=222,20
../../Scripts/foo.bat,sha256=444,40
../../Scripts/my_script.sh,sha256=333,30
"pkg/my file.py",sha256=abc,100
"../../Scripts/my tool.bat",sha256=def,200
"../../Include/my header.h",sha256=ghi,300
"../../my data.txt",sha256=jkl,400
foo-1.0.data/custom_dir/custom.txt,sha256=xyz,123
top_level/__init__.py,sha256=aaa,50
foo-1.0.dist-info/METADATA,sha256=bbb,60
foo-1.0.dist-info/RECORD,,
EOF

diff -u --strip-trailing-cr "$EXPECTED_WIN" "$WIN_OUT"
