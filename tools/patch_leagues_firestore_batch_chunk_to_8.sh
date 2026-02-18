#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

ROOT="lib/features/leagues"
TS=$(date +%s)

echo "[1/4] Show current chunkSize definitions (first 200 lines):"
grep -RIn "chunkSize" "$ROOT" | head -n 200 || true

echo
echo "[2/4] Backing up + patching: chunkSize = 450 -> 8"
FILES=$(grep -RIl "chunkSize\s*=\s*450" "$ROOT" || true)
if [ -n "${FILES}" ]; then
  for f in $FILES; do
    cp -f "$f" "$f.bak.$TS"
    perl -pi -e 's/chunkSize\s*=\s*450/chunkSize = 8/g' "$f"
    echo "Patched: $f"
  done
else
  echo "No chunkSize=450 found under $ROOT"
fi

echo
echo "[3/4] Also patch: const chunkSize = 9; -> 8 (optional safety)"
FILES9=$(grep -RIl "const\s+chunkSize\s*=\s*9;" "$ROOT" || true)
if [ -n "${FILES9}" ]; then
  for f in $FILES9; do
    cp -f "$f" "$f.bak9.$TS"
    perl -pi -e 's/const\s+chunkSize\s*=\s*9;/const chunkSize = 8;/g' "$f"
    echo "Patched: $f"
  done
else
  echo "No const chunkSize=9 found under $ROOT"
fi

echo
echo "[4/4] Verify no 450 remains:"
grep -RIn "chunkSize\s*=\s*450" "$ROOT" || echo "OK: no chunkSize=450 under $ROOT"

echo
echo "Done. Rebuild the app after this patch."
echo "Backups created as *.bak.$TS and *.bak9.$TS"
