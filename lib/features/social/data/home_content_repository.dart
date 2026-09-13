// lib/features/social/data/home_content_repository.dart
//
// Reads home_content/{id} — the admin-controlled Home Content CMS (see
// esportlyic-admin/lib/repositories/homeContentAdminRepository.ts for the
// schema and write path; public read / isSuperAdmin()-only write backstop
// in firestore.rules, actual gating via the admin app's home_content.manage
// permission). Three types share this collection:
//   - hero: top hero slot on the home tab
//   - promo_card: smaller cards in a promo strip
//   - announcement: shown as a dismissible modal bottom sheet on home load
//     (replaces the old platform_announcements inline banner)
//
// start/end scheduling is filtered client-side — there's no scheduled
// function flipping `active` automatically.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

enum HomeContentType { hero, promoCard, announcement }

HomeContentType _typeFromWire(String raw) {
  switch (raw) {
    case 'hero':
      return HomeContentType.hero;
    case 'announcement':
      return HomeContentType.announcement;
    case 'promo_card':
    default:
      return HomeContentType.promoCard;
  }
}

class HomeContentItem {
  const HomeContentItem({
    required this.id,
    required this.type,
    required this.title,
    required this.subtitle,
    required this.imageUrl,
    required this.ctaLabel,
    required this.ctaRoute,
    required this.severity,
    required this.order,
    required this.createdAtMs,
  });

  final String id;
  final HomeContentType type;
  final String title;
  final String subtitle;
  final String imageUrl;
  final String ctaLabel;
  final String ctaRoute;
  final String severity;
  final int order;
  final int createdAtMs;

  static bool _withinWindow(Map<String, dynamic> data, int nowMs) {
    final startAtMs = data['startAtMs'] is int ? data['startAtMs'] as int : null;
    final endAtMs = data['endAtMs'] is int ? data['endAtMs'] as int : null;
    if (startAtMs != null && nowMs < startAtMs) return false;
    if (endAtMs != null && nowMs > endAtMs) return false;
    return true;
  }

  factory HomeContentItem.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};
    return HomeContentItem(
      id: doc.id,
      type: _typeFromWire((data['type'] as String? ?? '').trim()),
      title: (data['title'] as String? ?? '').trim(),
      subtitle: (data['subtitle'] as String? ?? '').trim(),
      imageUrl: (data['imageUrl'] as String? ?? '').trim(),
      ctaLabel: (data['ctaLabel'] as String? ?? '').trim(),
      ctaRoute: (data['ctaRoute'] as String? ?? '').trim(),
      severity: (data['severity'] as String? ?? 'info').trim(),
      order: data['order'] is int ? data['order'] as int : 0,
      createdAtMs: data['createdAtMs'] is int ? data['createdAtMs'] as int : 0,
    );
  }
}

class HomeContentRepository {
  HomeContentRepository({FirebaseFirestore? firestore, FirebaseAuth? auth})
      : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  /// Streams all active home_content items within their schedule window, ordered by `order`.
  Stream<List<HomeContentItem>> watchActive() {
    return _firestore
        .collection('home_content')
        .where('active', isEqualTo: true)
        .orderBy('order')
        .snapshots()
        .map<List<HomeContentItem>>((snap) {
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      return snap.docs
          .where((d) => HomeContentItem._withinWindow(d.data(), nowMs))
          .map(HomeContentItem.fromDoc)
          .toList();
    }).handleError((Object _, StackTrace __) => <HomeContentItem>[]);
  }

  /// Marks the given announcement as seen by this user, mirroring
  /// PlatformAnnouncementsRepository.markAllSeen's per-user cursor pattern.
  Future<void> markAnnouncementSeen(int announcementCreatedAtMs) async {
    final uid = _auth.currentUser?.uid.trim() ?? '';
    if (uid.isEmpty) return;

    try {
      await _firestore.collection('users').doc(uid).set(
        <String, dynamic>{'lastSeenHomeAnnouncementAtMs': announcementCreatedAtMs},
        SetOptions(merge: true),
      );
    } catch (_) {}
  }
}
