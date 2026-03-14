import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../domain/master_league_plan.dart';
import 'master_league_payment_service.dart';

class MasterLeagueEntitlementException implements Exception {
  final String message;
  const MasterLeagueEntitlementException(this.message);

  @override
  String toString() => message;
}

class OrganizerProEntitlement {
  final bool active;
  final MasterLeaguePlan? plan;
  final int expiryMs;

  const OrganizerProEntitlement({
    required this.active,
    required this.plan,
    required this.expiryMs,
  });
}

class MasterLeagueEntitlementService {
  MasterLeagueEntitlementService({
    Object? firestore,
    FirebaseAuth? auth,
  }) : _auth = auth ?? FirebaseAuth.instance;

  final FirebaseAuth _auth;

  static const String _claimsActiveKey = 'organizerPro';
  static const String _claimsExpiryKey = 'organizerProExpiryMs';
  static const String _claimsPlanKey = 'organizerProPlan';

  static const String _providerFlutterwave = 'flutterwave';

  static const String _workerBaseUrl =
      String.fromEnvironment('EH_WORKER_BASE_URL', defaultValue: '');

  String _uidOrThrow() {
    final uid = _auth.currentUser?.uid.trim() ?? '';
    if (uid.isEmpty) {
      throw const MasterLeagueEntitlementException(
        'Please sign in and try again.',
      );
    }
    return uid;
  }

  MasterLeaguePlan? _claimPlanFromRaw(dynamic raw) {
    if (raw is! String) return null;
    final normalized = raw.trim().toLowerCase();
    if (normalized == 'basic') return MasterLeaguePlan.basic;
    if (normalized == 'pro') return MasterLeaguePlan.pro;
    if (normalized == 'elite') return MasterLeaguePlan.elite;
    return null;
  }

  int _planOrder(MasterLeaguePlan? plan) {
    if (plan == null) return 0;
    if (plan == MasterLeaguePlan.basic) return 1;
    if (plan == MasterLeaguePlan.pro) return 2;
    if (plan == MasterLeaguePlan.elite) return 3;
    return 0;
  }

  bool _planSatisfies({
    required MasterLeaguePlan actual,
    required MasterLeaguePlan requested,
  }) {
    return _planOrder(actual) >= _planOrder(requested);
  }

  Future<OrganizerProEntitlement> _readClaims({
    required bool forceRefresh,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      return const OrganizerProEntitlement(
        active: false,
        plan: null,
        expiryMs: 0,
      );
    }

    final tokenResult = await user.getIdTokenResult(forceRefresh);
    final claims = tokenResult.claims ?? <String, dynamic>{};

    final active = claims[_claimsActiveKey] == true;

    int expiryMs = 0;
    final rawExpiry = claims[_claimsExpiryKey];
    if (rawExpiry is int) expiryMs = rawExpiry;
    if (rawExpiry is num) expiryMs = rawExpiry.toInt();

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final notExpired = expiryMs > nowMs;

    final plan = _claimPlanFromRaw(claims[_claimsPlanKey]);

    final ok = active && notExpired && plan != null;

    return OrganizerProEntitlement(
      active: ok,
      plan: ok ? plan : null,
      expiryMs: ok ? expiryMs : 0,
    );
  }

  Stream<bool> watchUnlocked() {
    return _auth.idTokenChanges().asyncMap((_) async {
      try {
        final ent = await _readClaims(forceRefresh: false);
        return ent.active;
      } catch (_) {
        return false;
      }
    });
  }

  Future<bool> isUnlocked({bool forceRefresh = false}) async {
    _uidOrThrow();
    final ent = await _readClaims(forceRefresh: forceRefresh);
    return ent.active;
  }

  Future<MasterLeaguePlan?> getActivePlan({bool forceRefresh = false}) async {
    _uidOrThrow();
    final ent = await _readClaims(forceRefresh: forceRefresh);
    return ent.plan;
  }

  Uri _activateUri() {
    final base = _workerBaseUrl.trim();
    if (base.isEmpty) {
      throw const MasterLeagueEntitlementException(
        'Organizer Pro activation service is not configured. Please contact support.',
      );
    }

    final normalized =
        base.endsWith('/') ? base.substring(0, base.length - 1) : base;
    return Uri.parse('$normalized/organizer-pro/activate');
  }

  Future<Map<String, dynamic>> _postJson({
    required Uri uri,
    required String idToken,
    required Map<String, dynamic> body,
    Duration timeout = const Duration(seconds: 25),
  }) async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 12);

    try {
      final req = await client.postUrl(uri).timeout(timeout);
      req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $idToken');
      req.headers.set(HttpHeaders.contentTypeHeader, ContentType.json.mimeType);
      req.add(utf8.encode(jsonEncode(body)));

      final res = await req.close().timeout(timeout);
      final raw = await res.transform(utf8.decoder).join();

      Map<String, dynamic> parsed = <String, dynamic>{};
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          parsed = decoded.cast<String, dynamic>();
        }
      } catch (_) {
        parsed = <String, dynamic>{'raw': raw};
      }

      if (res.statusCode < 200 || res.statusCode >= 300) {
        final msg = (parsed['error'] as String?)?.trim();
        throw MasterLeagueEntitlementException(
          msg?.isNotEmpty == true
              ? msg!
              : 'Activation failed. Please try again.',
        );
      }

      return parsed;
    } on MasterLeagueEntitlementException {
      rethrow;
    } on SocketException {
      throw const MasterLeagueEntitlementException(
        'Your network appears to be offline. Please check your connection and try again.',
      );
    } on HandshakeException {
      throw const MasterLeagueEntitlementException(
        'Secure connection failed. Please try again.',
      );
    } on TimeoutException {
      throw const MasterLeagueEntitlementException(
        "We couldn't activate Organizer Pro right now. Please try again.",
      );
    } catch (_) {
      throw const MasterLeagueEntitlementException(
        "We couldn't activate Organizer Pro right now. Please try again.",
      );
    } finally {
      client.close(force: true);
    }
  }

  Future<OrganizerProEntitlement> _waitForClaims({
    required MasterLeaguePlan requestedPlan,
  }) async {
    const delays = <Duration>[
      Duration(milliseconds: 400),
      Duration(milliseconds: 800),
      Duration(seconds: 1),
      Duration(seconds: 2),
      Duration(seconds: 2),
      Duration(seconds: 3),
    ];

    OrganizerProEntitlement last = const OrganizerProEntitlement(
      active: false,
      plan: null,
      expiryMs: 0,
    );

    for (int i = 0; i < delays.length; i++) {
      last = await _readClaims(forceRefresh: true);
      if (last.active &&
          last.plan != null &&
          _planSatisfies(actual: last.plan!, requested: requestedPlan)) {
        return last;
      }
      await Future<void>.delayed(delays[i]);
    }

    return last;
  }

  Future<void> activateAfterPayment({
    required MasterLeaguePlan plan,
    required MasterLeaguePaymentResult payment,
  }) async {
    final uid = _uidOrThrow();

    if (payment.success != true) {
      throw const MasterLeagueEntitlementException('Payment not successful.');
    }

    final receiptId = (payment.receiptId ?? '').trim();
    if (receiptId.isEmpty) {
      throw const MasterLeagueEntitlementException('Missing receipt ID.');
    }

    final provider = payment.provider.trim().toLowerCase();
    if (provider != _providerFlutterwave) {
      throw MasterLeagueEntitlementException(
        'Unsupported payment provider: ${payment.provider}',
      );
    }

    final user = _auth.currentUser;
    if (user == null) {
      throw const MasterLeagueEntitlementException(
        'Please sign in and try again.',
      );
    }

    if (kDebugMode) {
      debugPrint(
        '[OrganizerPro] Activating via Worker: uid=$uid plan=${plan.id} receiptId=$receiptId',
      );
    }

    final idToken = await user.getIdToken();

    await _postJson(
      uri: _activateUri(),
      idToken: idToken,
      body: <String, dynamic>{
        'plan': plan.id,
        'provider': _providerFlutterwave,
        'receiptId': receiptId,
      },
    );

    final ent = await _waitForClaims(requestedPlan: plan);

    if (!ent.active || ent.plan == null) {
      throw const MasterLeagueEntitlementException(
        'Payment was successful, but Organizer Pro is not active yet. Please try again in a moment.',
      );
    }

    if (!_planSatisfies(actual: ent.plan!, requested: plan)) {
      throw MasterLeagueEntitlementException(
        'Organizer Pro activated, but plan mismatch detected. '
        'Expected at least ${plan.displayName}, got ${ent.plan?.displayName ?? 'unknown'}.',
      );
    }
  }
}
