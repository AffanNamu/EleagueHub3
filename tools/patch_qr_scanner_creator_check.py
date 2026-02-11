from __future__ import annotations
from pathlib import Path
import re

PATH = Path("lib/features/leagues/presentation/qr_scanner_screen.dart")
src = PATH.read_text(encoding="utf-8")

# Replace the whole _isCreator method body with UID-authoritative logic
pattern = re.compile(
    r"bool _isCreator\(League league, \{required String authUid, required String localUserId\}\)\s*\{.*?\n\s*\}",
    re.DOTALL
)

replacement = """bool _isCreator(League league, {required String authUid, required String localUserId}) {
    // Rules authority: organizerUid (Firebase UID)
    final orgUid = league.organizerUid.trim();
    if (authUid.trim().isNotEmpty && orgUid.isNotEmpty && orgUid == authUid.trim()) return true;

    // Backward compat (only for legacy local UI; not used for Firestore auth)
    final org = league.organizerUserId.trim();
    if (authUid.trim().isNotEmpty && org.isNotEmpty && org == authUid.trim()) return true;
    if (localUserId.trim().isNotEmpty && org.isNotEmpty && org == localUserId.trim()) return true;

    return false;
  }"""

if not pattern.search(src):
    raise SystemExit("Could not find _isCreator(...) method to patch. Search manually in qr_scanner_screen.dart.")

src = pattern.sub(replacement, src, count=1)
PATH.write_text(src, encoding="utf-8")
print("Patched:", PATH)
