// lib/core/services/rate_limit_service.dart
//
// Client-side counterpart to the rateLimitWriteValid()/rateLimitOk()
// functions in firestore.rules -- the RULES are the actual security
// boundary (a free user cannot bypass the cap no matter what this class
// does), this just builds the exact document shape those rules expect
// and gives callers a friendly "limit reached" signal before attempting
// a write that would otherwise fail with a raw permission-denied.
//
// Storage: users/{uid}/rateLimits/{kind}, one doc per (user, kind) pair,
// e.g. kind == 'chatMessages' (shared across league/organizer/global/DM
// chat) or 'feedPosts'. windowStart is a Firestore server timestamp --
// see the rules file for why a client-computed epoch-ms value can't be
// used for the equality check the rules perform.

import 'package:cloud_firestore/cloud_firestore.dart';

class RateLimitExceededException implements Exception {
  const RateLimitExceededException(this.kind);
  final String kind;

  /// Read by UserFriendlyError.toMessage() via dynamic `.message` access,
  /// same convention as the other *RepositoryException classes -- shown
  /// to the user verbatim, so it must already be a complete, friendly
  /// sentence.
  String get message {
    switch (kind) {
      case RateLimitService.kindChatMessages:
        return 'You have reached your free daily message limit '
            '(${RateLimitService.freeChatMessagesPerDay} per day). '
            'Upgrade to Pro or Elite to send without a daily limit.';
      case RateLimitService.kindFeedPosts:
        return 'You have reached your free daily post limit '
            '(${RateLimitService.freeFeedPostsPerDay} per day). '
            'Upgrade to Pro or Elite to post without a daily limit.';
      default:
        return 'You have reached your free daily limit for this action. '
            'Upgrade to Pro or Elite to remove it.';
    }
  }

  @override
  String toString() => message;
}

class RateLimitService {
  const RateLimitService._();

  static const String kindChatMessages = 'chatMessages';
  static const String kindFeedPosts = 'feedPosts';

  static const int freeChatMessagesPerDay = 2;
  static const int freeFeedPostsPerDay = 2;

  static const Duration _window = Duration(hours: 24);

  static DocumentReference<Map<String, dynamic>> _doc(String uid, String kind) {
    return FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('rateLimits')
        .doc(kind);
  }

  /// Runs [writeMore] inside a transaction that also increments (or starts
  /// a fresh rolling 24h window for) the given rate-limit counter, so the
  /// counter update and the actual write (a chat message, a feed post)
  /// commit together atomically -- matching what the Firestore rules
  /// require to consider the counter update "real".
  ///
  /// Throws [RateLimitExceededException] if the caller has already used
  /// today's quota (checked transactionally, so a race between two rapid
  /// sends still can't exceed [maxPerDay]).
  static Future<void> runWithLimit({
    required String uid,
    required String kind,
    required int maxPerDay,
    required void Function(Transaction tx) writeMore,
  }) async {
    final ref = _doc(uid, kind);

    await FirebaseFirestore.instance.runTransaction((tx) async {
      final snap = await tx.get(ref);
      final now = DateTime.now();

      Object nextWindowStart;
      int nextCount;

      if (!snap.exists) {
        nextWindowStart = FieldValue.serverTimestamp();
        nextCount = 1;
      } else {
        final data = snap.data() ?? const <String, dynamic>{};
        final windowStart = data['windowStart'];
        final storedCount = (data['count'] as num?)?.toInt() ?? 0;
        final windowStartAt = windowStart is Timestamp
            ? windowStart.toDate()
            : now.subtract(_window * 2); // treat malformed data as expired

        if (now.difference(windowStartAt) > _window) {
          nextWindowStart = FieldValue.serverTimestamp();
          nextCount = 1;
        } else {
          if (storedCount >= maxPerDay) {
            throw RateLimitExceededException(kind);
          }
          nextWindowStart = windowStart!;
          nextCount = storedCount + 1;
        }
      }

      tx.set(ref, <String, dynamic>{
        'windowStart': nextWindowStart,
        'count': nextCount,
      });

      writeMore(tx);
    });
  }
}
