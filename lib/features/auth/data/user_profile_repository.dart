import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart' show FirebaseException;

import '../models/user_profile.dart';

/// User-safe exception: if UI shows `$e`, it will still be a friendly message.
class UserFriendlyException implements Exception {
  final String message;
  const UserFriendlyException(this.message);

  @override
  String toString() => message;
}

class UserProfileRepository {
  UserProfileRepository({FirebaseFirestore? firestore}) : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _users => _firestore.collection('users');

  static bool _looksLikeShareId(String raw) {
    final s = raw.trim();
    // Example: eS44e35f (prefix eS + 4..12 alnum)
    return RegExp(r'^eS[A-Za-z0-9]{4,12}$').hasMatch(s);
  }

  static String _generateShareId(String userId) {
    // Deterministic, starts with eS, short for human sharing.
    return UserProfile.deriveShareIdFromUid(userId);
  }

  Never _rethrowFriendly(Object error) {
    if (error is UserFriendlyException) throw error;

    if (error is SocketException) {
      throw const UserFriendlyException(
        'Your network appears to be offline. Please check your connection and try again.',
      );
    }

    if (error is TimeoutException) {
      throw const UserFriendlyException('Your internet connection seems unstable. Please try again.');
    }

    if (error is FirebaseAuthException) {
      switch (error.code) {
        case 'network-request-failed':
          throw const UserFriendlyException(
            'Your network appears to be offline. Please check your connection and try again.',
          );
        case 'too-many-requests':
          throw const UserFriendlyException('Too many attempts. Please wait a moment and try again.');
        default:
          throw const UserFriendlyException("We couldn't complete this action. Please try again.");
      }
    }

    if (error is FirebaseException) {
      switch (error.code) {
        case 'unavailable':
        case 'deadline-exceeded':
          throw const UserFriendlyException(
            'Your network appears to be offline. Please check your connection and try again.',
          );
        case 'permission-denied':
          throw const UserFriendlyException('You don’t have permission to do that right now.');
        case 'unauthenticated':
          throw const UserFriendlyException('Please sign in and try again.');
        default:
          throw const UserFriendlyException("We couldn't load your profile right now. Please try again.");
      }
    }

    throw const UserFriendlyException('Something went wrong. Please try again.');
  }

  /// ONLINE-ONLY stream guard:
  /// - When Firestore emits a cache snapshot (offline / stale), emit the provided fallback instead.
  /// - When a stream errors, emit fallback (never leak raw errors to UI).
  Stream<T> _safeOnlineStream<T>({
    required Stream<DocumentSnapshot<Map<String, dynamic>>> source,
    required T Function(DocumentSnapshot<Map<String, dynamic>> snap) mapper,
    required T fallback,
  }) {
    return source.transform(
      StreamTransformer<DocumentSnapshot<Map<String, dynamic>>, T>.fromHandlers(
        handleData: (snap, sink) {
          // Online-only: do not treat cache/in-memory snapshots as authoritative.
          // Emit fallback so UI doesn't show stale data as "live".
          if (snap.metadata.isFromCache) {
            sink.add(fallback);
            return;
          }

          try {
            sink.add(mapper(snap));
          } catch (_) {
            sink.add(fallback);
          }
        },
        handleError: (error, stack, sink) {
          sink.add(fallback);
        },
      ),
    );
  }

  Future<bool> profileExists(String userId) async {
    try {
      final doc = await _users
          .doc(userId)
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 12));
      return doc.exists;
    } catch (e) {
      _rethrowFriendly(e is Object ? e : Exception('unknown'));
    }
  }

  Future<UserProfile?> fetchByUserId(String userId) async {
    try {
      final doc = await _users
          .doc(userId)
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 15));
      if (!doc.exists) return null;
      final data = doc.data();
      if (data == null) return null;
      return UserProfile.fromFirestore(userId: doc.id, data: data);
    } catch (e) {
      _rethrowFriendly(e is Object ? e : Exception('unknown'));
    }
  }

  Future<UserProfile?> fetchByShareId(String shareId) async {
    try {
      final sid = shareId.trim();
      if (sid.isEmpty) return null;

      final snap = await _users
          .where('shareId', isEqualTo: sid)
          .limit(1)
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 15));
      if (snap.docs.isEmpty) return null;

      final doc = snap.docs.first;
      return UserProfile.fromFirestore(userId: doc.id, data: doc.data());
    } catch (e) {
      _rethrowFriendly(e is Object ? e : Exception('unknown'));
    }
  }

  /// Accepts either:
  /// - Firebase uid (internal userId), or
  /// - short Share ID (e.g. eS44e35f)
  Future<UserProfile?> fetchByUserIdOrShareId(String userIdOrShareId) async {
    final key = userIdOrShareId.trim();
    if (key.isEmpty) return null;

    if (_looksLikeShareId(key)) {
      return fetchByShareId(key);
    }
    return fetchByUserId(key);
  }

  /// Resolves a shareId (eS...) to the real Firebase uid (doc id).
  Future<String?> resolveUserIdFromShareId(String shareId) async {
    try {
      final sid = shareId.trim();
      if (sid.isEmpty) return null;

      final snap = await _users
          .where('shareId', isEqualTo: sid)
          .limit(1)
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 15));
      if (snap.docs.isEmpty) return null;

      return snap.docs.first.id;
    } catch (e) {
      _rethrowFriendly(e is Object ? e : Exception('unknown'));
    }
  }

  Stream<UserProfile?> watchByUserId(String userId) {
    final src = _users.doc(userId).snapshots(includeMetadataChanges: true);

    return _safeOnlineStream<UserProfile?>(
      source: src,
      fallback: null,
      mapper: (doc) {
        if (!doc.exists) return null;
        final data = doc.data();
        if (data == null) return null;
        return UserProfile.fromFirestore(userId: doc.id, data: data);
      },
    );
  }

  Stream<bool> watchIsPremium(String userId) {
    final src = _users.doc(userId).snapshots(includeMetadataChanges: true);

    return _safeOnlineStream<bool>(
      source: src,
      fallback: false,
      mapper: (doc) {
        if (!doc.exists) return false;
        final data = doc.data();
        if (data == null) return false;
        return data['isPremium'] == true;
      },
    );
  }

  Stream<List<String>> watchQuickMessagesCustom(String userId) {
    final src = _users.doc(userId).snapshots(includeMetadataChanges: true);

    return _safeOnlineStream<List<String>>(
      source: src,
      fallback: const <String>[],
      mapper: (doc) {
        if (!doc.exists) return const <String>[];
        final data = doc.data();
        if (data == null) return const <String>[];

        final raw = data['quickMessagesCustom'];
        if (raw is! List) return const <String>[];

        return raw
            .map((e) => (e ?? '').toString().trim())
            .where((s) => s.isNotEmpty)
            .toList(growable: false);
      },
    );
  }

  Future<void> updateQuickMessagesCustom({
    required String userId,
    required List<String> messages,
  }) async {
    try {
      final cleaned = messages.map((e) => e.trim()).where((s) => s.isNotEmpty).toList(growable: false);

      await _users
          .doc(userId)
          .set(
            {
              'quickMessagesCustom': cleaned,
              'updatedAt': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true),
          )
          .timeout(const Duration(seconds: 20));
    } catch (e) {
      _rethrowFriendly(e is Object ? e : Exception('unknown'));
    }
  }

  Future<void> setPremium({
    required String userId,
    required bool isPremium,
  }) async {
    try {
      await _users
          .doc(userId)
          .set(
            {
              'isPremium': isPremium,
              'updatedAt': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true),
          )
          .timeout(const Duration(seconds: 20));
    } catch (e) {
      _rethrowFriendly(e is Object ? e : Exception('unknown'));
    }
  }

  Future<void> createProfileIfMissing({
    required String userId,
    required String teamName,
    required String authProvider,
    Map<String, dynamic>? onboardingAnswers,
  }) async {
    try {
      final ref = _users.doc(userId);

      await _firestore.runTransaction((tx) async {
        final snap = await tx.get(ref);
        if (snap.exists) return;

        final payload = <String, dynamic>{
          'userId': userId,
          'teamName': teamName,
          'authProvider': authProvider,
          'shareId': _generateShareId(userId),

          // Defaults for new users
          'isPremium': false,
          'quickMessagesCustom': <String>[],

          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        };

        if (onboardingAnswers != null && onboardingAnswers.isNotEmpty) {
          payload['onboardingAnswers'] = onboardingAnswers;
        }

        tx.set(ref, payload);
      }).timeout(const Duration(seconds: 25));
    } catch (e) {
      _rethrowFriendly(e is Object ? e : Exception('unknown'));
    }
  }

  Future<void> updateTeamName({
    required String userId,
    required String teamName,
  }) async {
    try {
      await _users
          .doc(userId)
          .set(
            {
              'teamName': teamName,
              'updatedAt': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true),
          )
          .timeout(const Duration(seconds: 20));
    } catch (e) {
      _rethrowFriendly(e is Object ? e : Exception('unknown'));
    }
  }
}
