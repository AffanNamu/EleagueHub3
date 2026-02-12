from __future__ import annotations
import re
from pathlib import Path

PATH = Path("lib/features/leagues/presentation/league_admin_screen.dart")
src = PATH.read_text(encoding="utf-8")

def replace_can_manage_coupons(s: str) -> str:
    # Replace the whole _canManageCoupons function body with UID-correct logic
    pattern = re.compile(r"bool _canManageCoupons\(League league\)\s*\{.*?\n\}", re.S)
    m = pattern.search(s)
    if not m:
        raise SystemExit("Could not find bool _canManageCoupons(League league) { ... }")

    new_fn = """bool _canManageCoupons(League league) {
    final auth = _currentAuthUid.trim();
    if (auth.isEmpty) return false;

    final ro = _remoteOrganizerUid.trim();
    final rw = _remoteOwnerUid.trim();

    // If we know remote owner ids, trust them (matches Firestore rules).
    if (ro.isNotEmpty || rw.isNotEmpty) {
      return ro == auth || rw == auth;
    }

    // OFFLINE / UNSYNCED fallback:
    // Use local organizerUid ONLY if it matches the current auth uid.
    final localOrgUid = league.organizerUid.trim();
    if (localOrgUid.isNotEmpty && localOrgUid == auth) return true;

    // Backward compat ONLY if organizerUserId actually stores Firebase UID.
    final legacy = league.organizerUserId.trim();
    return _looksLikeFirebaseUid(legacy) && legacy == auth;
  }"""
    return s[:m.start()] + new_fn + s[m.end():]

def replace_space_owner_check(s: str) -> str:
    # Replace legacy organizerUserId check blocks in _startSpace and _endSpace
    # by rules-authoritative UID check.
    old_block = """      if (_league!.organizerUserId.isNotEmpty && _league!.organizerUserId != currentUserId) {
        // Keep legacy behavior (space host uses local user id in current architecture).
        throw StateError(l10n.tr('league_admin_only_organizer_start_space'));
      }"""
    if old_block in s:
        new_block = """      final authUid = (FirebaseAuth.instance.currentUser?.uid ?? '').trim();
      if (authUid.isEmpty) {
        throw StateError(l10n.tr('league_admin_no_signed_in_user_error'));
      }

      final isOwnerByRules = _isRulesOwnerForLeague(
        _league!,
        authUid: authUid,
        remoteOrganizerUid: _remoteOrganizerUid,
        remoteOwnerUid: _remoteOwnerUid,
      );

      if (!isOwnerByRules) {
        throw StateError(l10n.tr('league_admin_only_organizer_start_space'));
      }"""
        s = s.replace(old_block, new_block)

    old_block2 = """      if (_league!.organizerUserId.isNotEmpty && _league!.organizerUserId != currentUserId) {
        // Keep legacy behavior (space host uses local user id in current architecture).
        throw StateError(l10n.tr('league_admin_only_organizer_end_space'));
      }"""
    if old_block2 in s:
        new_block2 = """      final authUid = (FirebaseAuth.instance.currentUser?.uid ?? '').trim();
      if (authUid.isEmpty) {
        throw StateError(l10n.tr('league_admin_no_signed_in_user_error'));
      }

      final isOwnerByRules = _isRulesOwnerForLeague(
        _league!,
        authUid: authUid,
        remoteOrganizerUid: _remoteOrganizerUid,
        remoteOwnerUid: _remoteOwnerUid,
      );

      if (!isOwnerByRules) {
        throw StateError(l10n.tr('league_admin_only_organizer_end_space'));
      }"""
        s = s.replace(old_block2, new_block2)

    return s

# Apply patches
src2 = src
src2 = replace_can_manage_coupons(src2)
src2 = replace_space_owner_check(src2)

PATH.write_text(src2, encoding="utf-8")
print("Patched:", PATH)
