// lib/features/social/data/platform_announcements_repository.dart
//
// NEW FILE. Reads platform_announcements/{id} — the collection already
// defined in firestore.rules (public read, isSuperAdmin()-only write via
// the mobile app; the web admin workspace writes here too, via a
// server-side Admin SDK path that bypasses that rule intentionally).
//
// Schema (defined here, since the rules file has no field validation
// on this collection — it's intentionally open):
//   id: string
//   title: string
//   message: string
//   severity: string ('info' | 'warning' | 'critical')
//   active: bool
//   createdAtMs: int
//   createdBy: string (admin uid)

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

class PlatformAnnouncement {
  const PlatformAnnouncement({
    required this.id,
    required this.title,
    required this.message,
    required this.severity,
    required this.createdAtMs,
  });

  final String id;
  final String title;
  final String message;
  final String severity;
  final int createdAtMs;

  factory PlatformAnnouncement.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};
    return PlatformAnnouncement(
      id: doc.id,
      title: (data['title'] as String? ?? '').trim(),
      message: (data['message'] as String? ?? '').trim(),
      severity: (data['severity'] as String? ?? 'info').trim(),
      createdAtMs: data['createdAtMs'] is int ? data['createdAtMs'] as int : 0,
    );
  }
}

class PlatformAnnouncementsRepository {
  PlatformAnnouncementsRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  /// Streams the single most recent ACTIVE announcement, or null if none
  /// (including on error — a missing composite index or offline state
  /// should never crash the home screen for what's a purely cosmetic
  /// banner; the caller sees null and simply shows nothing).
  ///
  /// Uses a StreamTransformer (not .handleError((_) {})) specifically
  /// because handleError's return value is discarded — it cannot emit a
  /// replacement value, only suppress the error, which would leave any
  /// StreamBuilder listening to this stuck on hasData == false forever.
  /// This is the same class of bug fixed in PrivateChatRepository.
  Stream<PlatformAnnouncement?> watchLatestActive() {
    return _firestore
        .collection('platform_announcements')
        .where('active', isEqualTo: true)
        .orderBy('createdAtMs', descending: true)
        .limit(1)
        .snapshots()
        .map<PlatformAnnouncement?>((snap) {
          if (snap.docs.isEmpty) return null;
          return PlatformAnnouncement.fromDoc(snap.docs.first);
        })
        .transform(
          StreamTransformer<PlatformAnnouncement?, PlatformAnnouncement?>.fromHandlers(
            handleError: (error, stackTrace, sink) {
              // Fail open to "no banner" rather than leaving the
              // StreamBuilder stuck on hasData == false forever.
              sink.add(null);
            },
          ),
        );
  }
}
