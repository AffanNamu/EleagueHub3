#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path
import re
import sys

TARGET = Path("lib/features/chat/presentation/league_chat_screen.dart")

# Match the buggy setState block that uses commas instead of semicolons.
# This is intentionally whitespace-tolerant.
PATTERN = re.compile(
    r"""
    setState\s*\(\s*\(\s*\)\s*\{\s*
    _isRecording\s*=\s*false\s*,\s*
    _recordingPath\s*=\s*null\s*,\s*
    \}\s*\)\s*;
    """,
    re.VERBOSE | re.MULTILINE,
)

REPLACEMENT = """setState(() {
        _isRecording = false;
        _recordingPath = null;
      });"""

def main() -> int:
    if not TARGET.exists():
        print(f"[ERROR] File not found: {TARGET}", file=sys.stderr)
        return 2

    s = TARGET.read_text(encoding="utf-8")

    if not PATTERN.search(s):
        print("[ERROR] Buggy setState block not found. Nothing patched.", file=sys.stderr)
        print("Open league_chat_screen.dart and search for '_cancelRecording' to fix manually:", file=sys.stderr)
        print("Replace commas with semicolons inside setState.", file=sys.stderr)
        return 3

    s2 = PATTERN.sub(REPLACEMENT, s, count=1)
    TARGET.write_text(s2, encoding="utf-8")
    print("[OK] Patched _cancelRecording() setState block (commas -> semicolons).")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
