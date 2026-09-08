// lib/core/analytics/link_analytics_service.dart
//
// LinkAnalyticsService — records sharing & deep-link analytics events to
// Firestore. Deliberately best-effort / fire-and-forget: analytics must
// NEVER block or fail a share action or a deep-link navigation, so every
// public method swallows its own errors after a debug-mode log.
//
// Firestore layout:
//   analytics_link_events/{eventId}
//     - eventType: 'share' | 'click'
//     - entityType: 'userProfile' | 'competition' | 'team' | 'post' |
//                   'organizerWorkspace' | ...
//     - entityId: string (id or username, whichever addresses the entity)
//     - channel: 'whatsapp' | 'telegram' | 'facebook' | 'x' | 'sms' |
//                'copy_link' | 'system_share' | 'deep_link' | 'web_direct'
//     - userId: uid of the actor, or '' if signed out
//     - createdAtMs: int
//
// A lightweight rollup is also maintained at:
//   analytics_link_rollups/{entityType}_{entityId}
//     - shareCount: int
//     - clickCount: int
//     - lastEventAtMs: int
// via FieldValue.increment, so a future dashboard can read aggregate
// counts without scanning the full event log.
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../routing/route_resolver.dart';

enum LinkEventType { share, click }

/// Where a share action was routed to, or how a deep link arrived.
class ShareChannel {
  const ShareChannel._(this.id);
  final String id;

  static const whatsapp = ShareChannel._('whatsapp');
  static const telegram = ShareChannel._('telegram');
  static const facebook = ShareChannel._('facebook');
  static const x = ShareChannel._('x');
  static const sms = ShareChannel._('sms');
  static const copyLink = ShareChannel._('copy_link');
  static const systemShare = ShareChannel._('system_share');
  static const deepLink = ShareChannel._('deep_link');
  static const webDirect = ShareChannel._('web_direct');

  @override
  String toString() => id;
}

class LinkAnalyticsService {
  LinkAnalyticsService._internal();
  static final LinkAnalyticsService instance =
      LinkAnalyticsService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _events =>
      _firestore.collection('analytics_link_events');

  CollectionReference<Map<String, dynamic>> get _rollups =>
      _firestore.collection('analytics_link_rollups');

  String _rollupId(ShareableEntityType type, String entityKey) =>
      '${type.name}_${entityKey.trim()}';

  /// Records that [entity] was shared via [channel]. Fire-and-forget.
  void recordShare({
    required ShareableEntity entity,
    required ShareChannel channel,
  }) {
    unawaited(_record(
      eventType: LinkEventType.share,
      entity: entity,
      channel: channel,
    ));
  }

  /// Records that a deep link / public URL for [entity] was opened.
  /// [channel] is typically [ShareChannel.deepLink] (came in through the
  /// OS "open with app" flow) or [ShareChannel.webDirect] (typed/loaded
  /// directly in a browser tab).
  void recordClick({
    required ShareableEntity entity,
    ShareChannel channel = ShareChannel.deepLink,
  }) {
    unawaited(_record(
      eventType: LinkEventType.click,
      entity: entity,
      channel: channel,
    ));
  }

  Future<void> _record({
    required LinkEventType eventType,
    required ShareableEntity entity,
    required ShareChannel channel,
  }) async {
    try {
      final entityKey = entity.username.trim().isNotEmpty
          ? entity.username.trim()
          : entity.id.trim();
      if (entityKey.isEmpty) return;

      final uid = FirebaseAuth.instance.currentUser?.uid.trim() ?? '';
      final now = DateTime.now().millisecondsSinceEpoch;

      final eventDoc = _events.doc();
      await eventDoc.set(<String, dynamic>{
        'eventId': eventDoc.id,
        'eventType': eventType == LinkEventType.share ? 'share' : 'click',
        'entityType': entity.type.name,
        'entityId': entityKey,
        'channel': channel.id,
        'userId': uid,
        'createdAtMs': now,
      }).timeout(const Duration(seconds: 10));

      final rollupRef = _rollups.doc(_rollupId(entity.type, entityKey));
      await rollupRef.set(
        <String, dynamic>{
          'entityType': entity.type.name,
          'entityId': entityKey,
          if (eventType == LinkEventType.share)
            'shareCount': FieldValue.increment(1),
          if (eventType == LinkEventType.click)
            'clickCount': FieldValue.increment(1),
          'lastEventAtMs': now,
        },
        SetOptions(merge: true),
      ).timeout(const Duration(seconds: 10));
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[LinkAnalyticsService] record failed (non-fatal): $e');
      }
    }
  }
}
