#!/bin/sh
set -eu

IN="$1"
OUT="$2"

if head -n 1 "$IN" | grep -q "^#!python"; then
  echo "#!/bin/sh" > "$OUT"
  # Polyglot re-exec gibberish.
  # Shell treats first line's quotes as a quoted command to execute. It then
  # re-execs itself with Python, which treats the triple quoted strings
  # as plain strings and ignores them.
  echo "'''exec' \"\$(dirname \"\$0\")/python3\" \"\$0\" \"\$@\"" >> "$OUT"
  echo "' '''" >> "$OUT"
  tail -n +2 "$IN" >> "$OUT"
else
  cp "$IN" "$OUT"
fi
chmod +x "$OUT"
