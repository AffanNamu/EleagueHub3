#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

TARGETS=$(grep -RIn --line-number "const chunkSize = 450;" lib | cut -d: -f1 | sort -u || true)

if [ -z "${TARGETS}" ]; then
  echo "No 'const chunkSize = 450;' found under lib/"
  exit 0
fi

echo "Patching these files:"
echo "$TARGETS"

TS=$(date +%s)
for f in $TARGETS; do
  cp -f "$f" "$f.bak.$TS"
  perl -pi -e 's/const chunkSize = 450;/const chunkSize = 9;/g' "$f"
done

echo "Done. Backups saved as *.bak.$TS"
