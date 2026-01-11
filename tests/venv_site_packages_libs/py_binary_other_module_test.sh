#
# Test that for a py_binary from a dependency module, we place links created via runfiles(...)
# in the right place. This tests the fix made for issues/3503
#

set -eu

# Helper to check links exist and where they point to
check_link() {
  link=$1

  # 1) Must exist
  if [ ! -e "$link" ]; then
    return 1
  fi

  # 2) Must be a symlink
  if [ ! -L "$link" ]; then
    return 1
  fi
}

ensure_link() {
  if ! check_link $1; then
    echo "ERROR: $link does not exist"
    return 1
  fi
}

cd ${RUNFILES_DIR}

# First do a tree of whole runfiles for easier debugging in case of failure
echo "[*] Runfile tree"
find .

# Sanity check that invalid files don't exist.
echo "[*] Sanity check our ensure_link function"
if check_link ./__I_DO_NOT_EXIST__; then
  echo "Check link function is broken"
  exit 1
fi

# Check the links exist in the correct place.
echo "[*] Testing existence of symlinks in the right place"
ensure_link ./other+/_venv_bin.venv/lib/python3.13/site-packages/nspkg/subnspkg/delta/__init__.py
ensure_link ./other+/_venv_bin.venv/lib/python3.13/site-packages/nspkg/subnspkg/gamma/__init__.py

# Finally, test that running the binary works, i.e imports are resolved.
echo "[*] Testing running the binary"
./other+/venv_bin
