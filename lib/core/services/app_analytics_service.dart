import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Lightweight analytics event logger to Firestore.
/// - Collection: analytics_events
/// - Rules: signed-in users can create; pricing admins can read.
/// - Best-effort: failures are swallowed; never crash production flows.
///
/// IMPORTANT (Rules compatibility):
/// Your Firestore rules for /analytics_events typically enforce:
/// - request.auth != null
/// - request.resource.data.userId == request.auth.uid
///
/// Therefore this service:
/// - Only logs when a FirebaseAuth user exists (otherwise it returns silently).
/// - Always writes `userId` as FirebaseAuth.currentUser.uid.
/// - If callers pass a different/legacy/local id, it is stored in `actorUserId`
///   (informational only; rules do not validate it).
class AppAnalyticsService {
  AppAnalyticsService._();
  static final AppAnalyticsService instance = AppAnalyticsService._();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static const Set<String> _reservedKeys = <String>{
    'eventName',
    'userId',
    'createdAtMs',
    'actorUserId',
  };

  int _nowMs() => DateTime.now().millisecondsSinceEpoch;

  String _authUidOrEmpty() => FirebaseAuth.instance.currentUser?.uid.trim() ?? '';

  Future<void> _log(Map<String, dynamic> data) async {
    try {
      await _firestore.collection('analytics_events').add(data);
    } catch (_) {
      // Best-effort: ignore failures.
    }
  }

  Map<String, dynamic> _sanitizeExtra(Map<String, Object?> extra) {
    final out = <String, dynamic>{};

    extra.forEach((key, value) {
      final k = key.trim();
      if (k.isEmpty) return;
      if (_reservedKeys.contains(k)) return;

      out[k] = _sanitizeValue(value);
    });

    return out;
  }

  dynamic _sanitizeValue(Object? v) {
    if (v == null) return null;

    // Primitive Firestore-safe types
    if (v is String || v is bool || v is int || v is double) return v;

    // num -> int/double
    if (v is num) return v.toDouble();

    // Timestamp / GeoPoint are Firestore-native
    if (v is Timestamp || v is GeoPoint) return v;

    // DateTime -> Timestamp
    if (v is DateTime) return Timestamp.fromDate(v);

    // Enum -> string
    if (v is Enum) return v.name;

    // List -> sanitize elements
    if (v is List) {
      return v.map((e) => _sanitizeValue(e)).toList(growable: false);
    }

    // Map -> sanitize keys/values (stringify keys)
    if (v is Map) {
      final m = <String, dynamic>{};
      v.forEach((k, val) {
        final kk = (k is String) ? k : k.toString();
        if (kk.trim().isEmpty) return;
        m[kk] = _sanitizeValue(val);
      });
      return m;
    }

    // Fallback: stringify unknown objects
    return v.toString();
  }

  /// Generic event.
  ///
  /// - `userId` parameter is treated as an optional *actor/legacy* id.
  /// - The stored `userId` field is ALWAYS the Firebase Auth UID (to satisfy rules).
  Future<void> logEvent({
    required String eventName,
    String? userId,
    Map<String, Object?> extra = const {},
  }) async {
    final authUid = _authUidOrEmpty();
    if (authUid.isEmpty) {
      // Rules deny unauthenticated writes. Skip silently.
      return;
    }

    final actor = (userId ?? '').trim();
    final payload = <String, dynamic>{
      ..._sanitizeExtra(extra),
      'eventName': eventName,
      // MUST equal request.auth.uid (rules requirement)
      'userId': authUid,
      'createdAtMs': _nowMs(),
      // Helpful for debugging legacy/local ids without breaking rules
      if (actor.isNotEmpty && actor != authUid) 'actorUserId': actor,
    };

    await _log(payload);
  }

  // Payment attempt (league creation or access/redemption)
  Future<void> logPaymentAttempt({
    required String kind, // 'creation' | 'access' | 'redemption'
    required String leagueId,
    required String leagueName,
    String provider = 'flutterwave',
    String currency = '',
    String amount = '0',
    String? userId,
  }) async {
    await logEvent(
      eventName: 'payment_attempt',
      userId: userId,
      extra: {
        'kind': kind,
        'leagueId': leagueId,
        'leagueName': leagueName,
        'provider': provider,
        'currency': currency,
        'amount': amount,
      },
    );
  }

  // Payment result
  Future<void> logPaymentResult({
    required String kind, // 'creation' | 'access' | 'redemption'
    required String leagueId,
    required String leagueName,
    required bool success,
    String provider = 'flutterwave',
    String currency = '',
    String amount = '0',
    String? receiptId,
    String? errorMessage,
    String? userId,
  }) async {
    await logEvent(
      eventName: success ? 'payment_success' : 'payment_failed',
      userId: userId,
      extra: {
        'kind': kind,
        'leagueId': leagueId,
        'leagueName': leagueName,
        'provider': provider,
        'currency': currency,
        'amount': amount,
        'receiptId': receiptId ?? '',
        if (!success) 'error': errorMessage ?? '',
      },
    );
  }

  // Coupon redemption lifecycle
  Future<void> logRedemptionPrepared({
    required String leagueId,
    required String leagueName,
    required String currency,
    required double expectedAmount,
    String? userId,
  }) async {
    await logEvent(
      eventName: 'redemption_prepared',
      userId: userId,
      extra: {
        'leagueId': leagueId,
        'leagueName': leagueName,
        'currency': currency,
        'expectedAmount': expectedAmount,
      },
    );
  }

  Future<void> logRedemptionResult({
    required String leagueId,
    required String leagueName,
    required bool success,
    required String currency,
    double chargedAmount = 0,
    String? receiptId,
    String? errorMessage,
    String? userId,
  }) async {
    await logEvent(
      eventName: success ? 'redemption_paid' : 'redemption_failed',
      userId: userId,
      extra: {
        'leagueId': leagueId,
        'leagueName': leagueName,
        'currency': currency,
        'chargedAmount': chargedAmount,
        'receiptId': receiptId ?? '',
        if (!success) 'error': errorMessage ?? '',
      },
    );
  }
}
