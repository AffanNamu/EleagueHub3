#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

F="lib/features/leagues/data/leagues_repository_local.dart"
TS=$(date +%s)

if [ ! -f "$F" ]; then
  echo "File not found: $F"
  exit 1
fi

cp -f "$F" "$F.bak.$TS"

# Patch common chunk sizes that cause permission-denied with get() rules
perl -pi -e 's/const chunkSize = 450;/const chunkSize = 8;/g' "$F"
perl -pi -e 's/const chunkSize = 9;/const chunkSize = 8;/g' "$F"

echo "Patched: $F"
echo "Backup:  $F.bak.$TS"
echo
echo "Verify chunkSize values now:"
grep -n "chunkSize" "$F" | head -n 200
