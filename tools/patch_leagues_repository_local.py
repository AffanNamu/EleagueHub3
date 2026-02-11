from __future__ import annotations
from pathlib import Path
import re

PATH = Path("lib/features/leagues/data/leagues_repository_local.dart")
src = PATH.read_text(encoding="utf-8")

# 1) Ensure firebase_auth import exists
if "package:firebase_auth/firebase_auth.dart" not in src:
    # Insert after cloud_firestore import line
    src = src.replace(
        "import 'package:cloud_firestore/cloud_firestore.dart';\n",
        "import 'package:cloud_firestore/cloud_firestore.dart';\n"
        "import 'package:firebase_auth/firebase_auth.dart';\n"
    )

# 2) Patch createLeagueLocally: infer/preserve organizerUid
# Find stored = league.copyWith( organizerUserId: organizerUserId, code: code, updatedAtMs: now, );
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

# 3) Patch joinLeagueLocallyByCode: arrayUnion must include auth uid (rules)
# Replace the set() payload block that currently uses arrayUnion([userId]).
needle = (
    "      await firestore.collection('leagues').doc(leagueId).set(\n"
    "        {\n"
    "          'memberIds': FieldValue.arrayUnion([userId]),\n"
    "          'updatedAtMs': now,\n"
    "        },\n"
    "        SetOptions(merge: true),\n"
    "      );\n"
)

if needle in src:
    repl = (
        "      final authUid = FirebaseAuth.instance.currentUser?.uid ?? '';\n"
        "      final idsToAdd = <String>[];\n"
        "      if (authUid.trim().isNotEmpty) idsToAdd.add(authUid.trim());\n"
        "      if (userId.trim().isNotEmpty && userId.trim() != authUid.trim()) idsToAdd.add(userId.trim());\n\n"
        "      await firestore.collection('leagues').doc(leagueId).set(\n"
        "        {\n"
        "          // RULES AUTH: request.auth.uid must become a member.\n"
        "          'memberIds': FieldValue.arrayUnion(idsToAdd),\n"
        "          'updatedAtMs': now,\n"
        "        },\n"
        "        SetOptions(merge: true),\n"
        "      );\n"
    )
    src = src.replace(needle, repl)

# 4) Patch offline join queue payload to include authUid (best-effort; safe if ignored)
offline_needle = (
    "      await _queue.enqueue(\n"
    "        id: _uuid.v4(),\n"
    "        entityType: 'league_join',\n"
    "        entityId: generatedLeagueId,\n"
    "        action: 'join',\n"
    "        lastModified: now,\n"
    "        payload: {\n"
    "          'code': code,\n"
    "          'userId': userId,\n"
    "        },\n"
    "      );\n"
)

if offline_needle in src:
    repl = (
        "      final authUid = FirebaseAuth.instance.currentUser?.uid ?? '';\n"
        "      await _queue.enqueue(\n"
        "        id: _uuid.v4(),\n"
        "        entityType: 'league_join',\n"
        "        entityId: generatedLeagueId,\n"
        "        action: 'join',\n"
        "        lastModified: now,\n"
        "        payload: {\n"
        "          'code': code,\n"
        "          // local/offline id (legacy)\n"
        "          'userId': userId,\n"
        "          // rules-authoritative id (preferred)\n"
        "          if (authUid.trim().isNotEmpty) 'authUid': authUid.trim(),\n"
        "        },\n"
        "      );\n"
    )
    src = src.replace(offline_needle, repl)

PATH.write_text(src, encoding="utf-8")
print("Patched:", PATH)
