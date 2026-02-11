from __future__ import annotations
import re
from pathlib import Path

PATH = Path("lib/features/leagues/presentation/league_admin_screen.dart")

src = PATH.read_text(encoding="utf-8")

def ensure_insert_after(needle: str, insert: str) -> None:
    global src
    if insert.strip() in src:
        return
    i = src.find(needle)
    if i < 0:
        raise SystemExit(f"Could not find needle: {needle}")
    i_end = i + len(needle)
    src = src[:i_end] + insert + src[i_end:]

def ensure_insert_before(needle: str, insert: str) -> None:
    global src
    if insert.strip() in src:
        return
    i = src.find(needle)
    if i < 0:
        raise SystemExit(f"Could not find needle: {needle}")
    src = src[:i] + insert + src[i:]

# 1) Add remote organizer/owner uid state fields after _currentAuthUid
REMOTE_FIELDS = """
  /// Remote, rules-authoritative organizer/owner UIDs from Firestore league doc.
  /// Used to ensure coupon admin UI matches server-side rules (Firebase UID only).
  String _remoteOrganizerUid = '';
  String _remoteOwnerUid = '';
"""
if "_remoteOrganizerUid" not in src:
    ensure_insert_after("  String _currentAuthUid = '';\n", REMOTE_FIELDS)

# 2) Add helper _canManageCoupons right after _isOrganizer(League league) function
if "bool _canManageCoupons(League league)" not in src:
    # Insert after the closing brace of _isOrganizer
    m = re.search(r"bool _isOrganizer\(League league\)\s*\{", src)
    if not m:
        raise SystemExit("Could not find _isOrganizer(League league) {")

    # Brace-match to find end of function
    start = m.end()
    depth = 1
    i = start
    while i < len(src) and depth > 0:
        c = src[i]
        if c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
        i += 1
    if depth != 0:
        raise SystemExit("Brace matching failed for _isOrganizer")

    insert_pos = i  # after closing brace

    helper = """

  /// Coupon admin permission must match Firestore rules.
  /// Firebase UID is the ONLY authority; short/share IDs are display-only.
  ///
  /// We prefer the remote league doc fields:
  /// - organizerUid / ownerUid
  /// and fall back ONLY if organizerUserId happens to store the Firebase UID.
  bool _canManageCoupons(League league) {
    final auth = _currentAuthUid.trim();
    if (auth.isEmpty) return false;

    final ro = _remoteOrganizerUid.trim();
    final rw = _remoteOwnerUid.trim();
    if (ro.isNotEmpty || rw.isNotEmpty) {
      return ro == auth || rw == auth;
    }

    // Fallback: safe only when organizerUserId is actually a Firebase UID.
    return league.organizerUserId.trim() == auth;
  }
"""
    src = src[:insert_pos] + helper + src[insert_pos:]

# 3) Patch _loadLeague() to also fetch remote organizerUid/ownerUid
# Add local vars remoteOrganizerUid/remoteOwnerUid near existing vars
if "String remoteOrganizerUid = '';" not in src:
    src = src.replace(
        "    bool showAddMe = false;\n    String currentUserId = '';\n    String currentAuthUid = '';\n",
        "    bool showAddMe = false;\n"
        "    String currentUserId = '';\n"
        "    String currentAuthUid = '';\n"
        "    String remoteOrganizerUid = '';\n"
        "    String remoteOwnerUid = '';\n"
    )

# Inject remote fetch inside the try block after current ids resolved
REMOTE_FETCH_BLOCK = r"""
      // Fetch rules-authoritative organizer/owner uid from Firestore.
      // This prevents UI from treating short/share IDs as admin identity.
      try {
        final snap = await FirebaseFirestore.instance
            .collection('leagues')
            .doc(widget.leagueId)
            .get();
        final data = snap.data();
        if (data != null) {
          remoteOrganizerUid = (data['organizerUid'] as String?)?.trim() ?? '';
          remoteOwnerUid = (data['ownerUid'] as String?)?.trim() ?? '';

          // Backward compat ONLY if legacy fields contain Firebase UID and match current auth.
          if (remoteOrganizerUid.isEmpty) {
            final legacyOrg = (data['organizerUserId'] as String?)?.trim() ?? '';
            if (legacyOrg.isNotEmpty && legacyOrg == currentAuthUid) {
              remoteOrganizerUid = currentAuthUid;
            }
          }
          if (remoteOwnerUid.isEmpty) {
            final legacyOwner = (data['ownerId'] as String?)?.trim() ?? '';
            if (legacyOwner.isNotEmpty && legacyOwner == currentAuthUid) {
              remoteOwnerUid = currentAuthUid;
            }
          }
        }
      } catch (_) {
        // ignore (offline / denied / missing)
      }
"""

if "Fetch rules-authoritative organizer/owner uid" not in src:
    # place after: currentUserId = await CurrentUser.getUserId();
    src = src.replace(
        "      currentAuthUid = FirebaseAuth.instance.currentUser?.uid ?? '';\n      currentUserId = await CurrentUser.getUserId();\n",
        "      currentAuthUid = FirebaseAuth.instance.currentUser?.uid ?? '';\n"
        "      currentUserId = await CurrentUser.getUserId();\n"
        + REMOTE_FETCH_BLOCK + "\n"
    )

# Assign remote values in setState
if "_remoteOrganizerUid =" not in src:
    src = src.replace(
        "      _currentAuthUid = currentAuthUid;\n",
        "      _currentAuthUid = currentAuthUid;\n"
        "      _remoteOrganizerUid = remoteOrganizerUid;\n"
        "      _remoteOwnerUid = remoteOwnerUid;\n"
    )

# 4) Replace coupon admin checks to use _canManageCoupons
src = src.replace("    if (!_isOrganizer(league)) {", "    if (!_canManageCoupons(league)) {")
src = src.replace("        if (league != null && _isOrganizer(league))", "        if (league != null && _canManageCoupons(league))")
src = src.replace("        if (league != null && _isOrganizer(league))", "        if (league != null && _canManageCoupons(league))")

# There are usually two occurrences in settings list; ensure all are replaced
src = src.replace("if (league != null && _isOrganizer(league))", "if (league != null && _canManageCoupons(league))")

# 5) Add guard at start of _showCouponCodesSheet()
if "Only the organizer can manage coupon codes." not in src:
    src = src.replace(
        "  void _showCouponCodesSheet() {\n    final league = _league;\n    if (league == null) return;\n",
        "  void _showCouponCodesSheet() {\n"
        "    final league = _league;\n"
        "    if (league == null) return;\n"
        "    if (!_canManageCoupons(league)) {\n"
        "      ScaffoldMessenger.of(context).showSnackBar(\n"
        "        const SnackBar(\n"
        "          content: Text('Only the organizer can manage coupon codes.'),\n"
        "          behavior: SnackBarBehavior.floating,\n"
        "        ),\n"
        "      );\n"
        "      return;\n"
        "    }\n"
    )

PATH.write_text(src, encoding="utf-8")
print("Patched:", PATH)
