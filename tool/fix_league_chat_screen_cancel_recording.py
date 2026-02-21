#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path
import sys

TARGET = Path("lib/features/chat/presentation/league_chat_screen.dart")

BAD = """      if (!mounted) return;
      setState(() {
        _isRecording = false,
        _recordingPath = null,
      });
"""

GOOD = """      if (!mounted) return;
      setState(() {
        _isRecording = false;
        _recordingPath = null;
      });
"""

def main() -> int:
  if not TARGET.exists():
    print(f"[ERROR] Target file not found: {TARGET}", file=sys.stderr)
    return 2

  s = TARGET.read_text(encoding="utf-8")
  if BAD not in s:
    print("[ERROR] Expected buggy snippet not found. No changes made.", file=sys.stderr)
    print("If you already changed it manually, you can ignore this.", file=sys.stderr)
    return 3

  s2 = s.replace(BAD, GOOD)
  TARGET.write_text(s2, encoding="utf-8")
  print("[OK] Patched _cancelRecording() setState block (comma -> semicolon).")
  return 0

if __name__ == "__main__":
  raise SystemExit(main())
