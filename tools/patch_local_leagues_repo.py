from __future__ import annotations
from pathlib import Path
import re

PATH = Path("lib/features/leagues/data/leagues_repository_local.dart")
src = PATH.read_text(encoding="utf-8")

# ensure firebase_auth import
if "package:firebase_auth/firebase_auth.dart" not in src:
    src = src.replace(
        "import 'package:cloud_firestore/cloud_firestore.dart';\n",
        "import 'package:cloud_firestore/cloud_firestore.dart';\n"
        "import 'package:firebase_auth/firebase_auth.dart';\n"
    )

# Patch createLeagueLocally: set organizerUid and membership userId to auth uid when present
# Replace stored = league.copyWith(organizerUserId: organizerUserId, code: code, updatedAtMs: now,)
pattern = re.compile(
    r"final stored = league\.copyWith\(\s*"
    r"organizerUserId:\s*organizerUserId,\s*"
    r"code:\s*code,\s*"
    r"updatedAtMs:\s*now,\s*"
    r"\);\s*",
    re.MULTILINE
)

if pattern.search(src):
    replacement = (
        "    final authUid = FirebaseAuth.instance.currentUser?.uid ?? '';\n"
        "    final inferredOrganizerUid = league.organizerUid.trim().isNotEmpty\n"
        "        ? league.organizerUid.trim()\n"
        "        : (authUid.trim().isNotEmpty\n"
        "            ? authUid.trim()\n"
        "            : (organizerUserId.trim().length > 20 ? organizerUserId.trim() : ''));\n\n"
        "    final stored = league.copyWith(\n"
        "      organizerUid: inferredOrganizerUid,\n"
        "      organizerUserId: organizerUserId,\n"
        "      code: code,\n"
        "      updatedAtMs: now,\n"
        "    );\n"
    )
    src = pattern.sub(replacement, src, count=1)

# Patch organizer membership creation: use auth uid when available
# Find Membership(... userId: organizerUserId, ... role: organizer ...)
src = src.replace(
    "      userId: organizerUserId,\n",
    "      userId: (FirebaseAuth.instance.currentUser?.uid ?? '').trim().isNotEmpty\n"
    "          ? (FirebaseAuth.instance.currentUser!.uid.trim())\n"
    "          : organizerUserId,\n"
)

PATH.write_text(src, encoding="utf-8")
print("Patched:", PATH)
