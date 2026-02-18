#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

ROOT="lib/features/leagues"
TS=$(date +%s)

echo "Searching for chunkSize in: $ROOT"
MATCHES=$(grep -RIn "chunkSize" "$ROOT" || true)
echo "$MATCHES" | head -n 120

echo
echo "Patching any 'chunkSize = 450' -> 'chunkSize = 8' under $ROOT ..."
FILES=$(grep -RIl "chunkSize\s*=\s*450" "$ROOT" || true)
if [ -z "${FILES}" ]; then
  echo "No chunkSize=450 found under $ROOT"
else
  echo "$FILES" | while read -r f; do
    [ -z "$f" ] && continue
    cp -f "$f" "$f.bak.$TS"
    perl -pi -e 's/chunkSize\s*=\s*450/chunkSize = 8/g' "$f"
    echo "Patched: $f"
  done
  echo "Backups: *.bak.$TS"
fi

echo
echo "Now verify no 450 remains:"
grep -RIn "chunkSize\s*=\s*450" "$ROOT" || echo "OK: no chunkSize=450 under $ROOT"
