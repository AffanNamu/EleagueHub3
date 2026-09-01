import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Centralized, runtime-loaded admins list (from /app/admins).
/// - Used to allow more pricing-admin UIDs without app updates.
/// - Firestore rules allow reads to /app/admins for signed-in users.
///
/// Firestore doc shape (collection: app, doc: admins)
/// {
///   "pricingAdmins": ["uid1", "uid2", ...]
/// }
class AppAdminsService {
  AppAdminsService._();
  static final AppAdminsService instance = AppAdminsService._();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // IMPORTANT:
  // Pricing admin IDs MUST be FirebaseAuth UIDs.
  // Share IDs / short IDs must never be treated as admins (UI would show admin tools but rules will deny writes).
  bool _looksLikeFirebaseUid(String s) => s.trim().length > 20;

  static const Set<String> _staticPricingAdmins = {
    'QhYeBpvAoRV6j0xGigHkBth4qIG3',
  };

  final Set<String> _dynamicPricingAdmins = <String>{};

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _sub;
  bool _started = false;

  void ensureStarted() {
    if (_started) return;

    // Auth rule: do not assume a user locally; only start when FirebaseAuth has a current user.
    final uid = FirebaseAuth.instance.currentUser?.uid.trim() ?? '';
    if (uid.isEmpty) return;

    _started = true;

    _sub = _firestore.collection('app').doc('admins').snapshots(includeMetadataChanges: true).listen(
      (snap) {
        try {
          // Online-only: ignore cache snapshots to avoid using stale admin lists while offline.
          if (snap.metadata.isFromCache) return;

          _dynamicPricingAdmins.clear();
          if (!snap.exists) return;

          final data = (snap.data() ?? <String, dynamic>{});
          final list = data['pricingAdmins'];
          if (list is! List) return;

          for (final v in list) {
            if (v is! String) continue;
            final s = v.trim();
            // Only accept real Firebase UIDs
            if (s.isNotEmpty && _looksLikeFirebaseUid(s)) {
              _dynamicPricingAdmins.add(s);
            }
          }
        } catch (_) {
          // best-effort: ignore
        }
      },
      onError: (_) {
        // best-effort: ignore (offline/perms/etc.)
      },
    );
  }

  bool isPricingAdminUid(String? uid) {
    final u = (uid ?? '').trim();
    if (u.isEmpty) return false;
    if (!_looksLikeFirebaseUid(u)) return false; // never treat short/share id as admin
    return _staticPricingAdmins.contains(u) || _dynamicPricingAdmins.contains(u);
  }

  Set<String> currentPricingAdmins() {
    // Only UIDs (defensive)
    final all = <String>{..._staticPricingAdmins, ..._dynamicPricingAdmins};
    return all.where(_looksLikeFirebaseUid).toSet();
  }

  Future<void> dispose() async {
    await _sub?.cancel();
    _sub = null;
    _started = false;
    _dynamicPricingAdmins.clear();
  }
}
