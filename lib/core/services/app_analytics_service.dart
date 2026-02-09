import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Lightweight analytics event logger to Firestore.
/// - Collection: analytics_events
/// - Rules: signed-in users can create; pricing admins can read.
/// - Best-effort: failures are swallowed; never crash production flows.
class AppAnalyticsService {
  AppAnalyticsService._();
  static final AppAnalyticsService instance = AppAnalyticsService._();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<void> _log(Map<String, dynamic> data) async {
    try {
      await _firestore.collection('analytics_events').add(data);
    } catch (_) {
      // Best-effort: ignore failures.
    }
  }

  int _nowMs() => DateTime.now().millisecondsSinceEpoch;

  String _uidOrAnonymous(String? uid) => (uid == null || uid.trim().isEmpty) ? 'anonymous' : uid;

  // Generic event
  Future<void> logEvent({
    required String eventName,
    String? userId,
    Map<String, Object?> extra = const {},
  }) async {
    final uid = _uidOrAnonymous(userId ?? FirebaseAuth.instance.currentUser?.uid);
    final payload = <String, dynamic>{
      'eventName': eventName,
      'userId': uid,
      'createdAtMs': _nowMs(),
      ...extra,
    };
    await _log(payload);
  }

  // Payment attempt (league creation or access)
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
