#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path
import sys
import re

TARGET = Path("lib/features/chat/presentation/league_chat_screen.dart")

def main() -> int:
    if not TARGET.exists():
        print(f"[ERROR] File not found: {TARGET}", file=sys.stderr)
        return 2

    s = TARGET.read_text(encoding="utf-8")

    # Patch the exact syntax issue causing your build failure:
    # Dart does not allow comma-separated statements in a block.
    #
    # We patch BOTH lines wherever they occur (safe + deterministic for this bug),
    # including variants with whitespace.
    patterns = [
        (re.compile(r"_isRecording\s*=\s*false\s*,\s*$", re.MULTILINE), "_isRecording = false;"),
        (re.compile(r"_recordingPath\s*=\s*null\s*,\s*$", re.MULTILINE), "_recordingPath = null;"),
    ]

    before = s
    for rx, repl in patterns:
        s = rx.sub(repl, s)

    if s == before:
        print("[ERROR] No occurrences found to patch.", file=sys.stderr)
        print("Search manually in league_chat_screen.dart for:", file=sys.stderr)
        print("  _isRecording = false,", file=sys.stderr)
        print("  _recordingPath = null,", file=sys.stderr)
        return 3

    TARGET.write_text(s, encoding="utf-8")
    print("[OK] Patched comma-terminated assignments to semicolons in league_chat_screen.dart")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
