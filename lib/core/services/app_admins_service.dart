import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

/// Centralized, runtime-loaded admins list (from /app/admins).
/// - Used to allow more pricing-admin UIDs without app updates.
/// - Firestore rules already allow reads to /app/admins for signed-in users.
///
/// Firestore doc shape (collection: app, doc: admins)
/// {
///   "pricingAdmins": ["uid1", "uid2", ...]
/// }
class AppAdminsService {
  AppAdminsService._();
  static final AppAdminsService instance = AppAdminsService._();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static const Set<String> _staticPricingAdmins = {
    'a0JDUelQW3TEyoXTm4ESuGi7ndq1',
  };

  final Set<String> _dynamicPricingAdmins = <String>{};

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _sub;
  bool _started = false;

  void ensureStarted() {
    if (_started) return;
    _started = true;

    _sub = _firestore.collection('app').doc('admins').snapshots().listen(
      (snap) {
        try {
          _dynamicPricingAdmins.clear();
          if (snap.exists) {
            final data = (snap.data() ?? <String, dynamic>{});
            final list = data['pricingAdmins'];
            if (list is List) {
              for (final v in list) {
                if (v is String && v.trim().isNotEmpty) {
                  _dynamicPricingAdmins.add(v.trim());
                }
              }
            }
          }
        } catch (_) {
          // ignore: best-effort
        }
      },
      onError: (_) {
        // ignore: best-effort
      },
    );
  }

  bool isPricingAdminUid(String? uid) {
    final u = (uid ?? '').trim();
    if (u.isEmpty) return false;
    return _staticPricingAdmins.contains(u) || _dynamicPricingAdmins.contains(u);
  }

  Set<String> currentPricingAdmins() {
    return <String>{..._staticPricingAdmins, ..._dynamicPricingAdmins};
  }

  Future<void> dispose() async {
    await _sub?.cancel();
    _sub = null;
    _started = false;
  }
}
