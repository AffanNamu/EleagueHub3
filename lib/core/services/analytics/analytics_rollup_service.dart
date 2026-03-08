import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

class AnalyticsRollupService {
  AnalyticsRollupService._();
  static final AnalyticsRollupService instance = AnalyticsRollupService._();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  int _nowMs() => DateTime.now().millisecondsSinceEpoch;

  String _dayIdUtcFromMs(int ms) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
    final yyyy = d.year.toString().padLeft(4, '0');
    final mm = d.month.toString().padLeft(2, '0');
    final dd = d.day.toString().padLeft(2, '0');
    return '$yyyy-$mm-$dd';
  }

  double _asDouble(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v.trim()) ?? 0.0;
    return 0.0;
  }

  int _asInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v.trim()) ?? 0;
    return 0;
  }

  /// Spark-plan rollup rebuild:
  /// - success attempts: status == client_success
  /// - failed attempts: status in [cancelled, client_failed]
  ///
  /// Writes:
  /// - analytics_summary/global
  /// - revenue_by_day/{YYYY-MM-DD}
  Future<void> rebuild({int daysBack = 30}) async {
    final nowUtc = DateTime.now().toUtc();
    final fromUtc = nowUtc.subtract(Duration(days: daysBack));
    final fromMs = fromUtc.millisecondsSinceEpoch;

    int successfulPayments = 0;
    int failedPayments = 0;
    int couponsSold = 0;

    final revenueTotals = <String, double>{'NGN': 0.0, 'USD': 0.0};
    final byProductType = <String, dynamic>{};

    final byDay = <String, Map<String, dynamic>>{};

    Future<void> consume(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs, {required bool success}) async {
      for (final doc in docs) {
        final data = doc.data();

        final currency = (data['currency'] ?? 'USD').toString().trim().toUpperCase();
        final amount = _asDouble(data['amount']);

        final paidAtMs = _asInt(data['paidAtMs']);
        final createdAtMs = _asInt(data['createdAtMs']);
        final tsMs = (paidAtMs > 0) ? paidAtMs : (createdAtMs > 0 ? createdAtMs : _nowMs());

        final dayId = _dayIdUtcFromMs(tsMs);

        byDay.putIfAbsent(dayId, () {
          return <String, dynamic>{
            'dayId': dayId,
            'successfulPayments': 0,
            'failedPayments': 0,
            'leaguesCreated': 0,
            'revenue': <String, double>{'NGN': 0.0, 'USD': 0.0},
            'byProductType': <String, dynamic>{},
          };
        });

        final day = byDay[dayId]!;
        if (success) {
          successfulPayments++;
          day['successfulPayments'] = (day['successfulPayments'] as int) + 1;

          revenueTotals[currency] = (revenueTotals[currency] ?? 0.0) + amount;
          final dayRevenue = (day['revenue'] as Map).cast<String, dynamic>();
          dayRevenue[currency] = _asDouble(dayRevenue[currency]) + amount;
        } else {
          failedPayments++;
          day['failedPayments'] = (day['failedPayments'] as int) + 1;
        }

        final items = (data['items'] is List) ? (data['items'] as List) : const [];
        for (final it in items) {
          if (it is! Map) continue;
          final m = it.cast<String, dynamic>();

          final type = (m['productType'] ?? '').toString().trim();
          if (type.isEmpty) continue;

          final itAmount = _asDouble(m['amount']);
          final qty = _asInt(m['quantity']);

          if (success && type.toLowerCase() == 'coupon') {
            couponsSold += qty < 0 ? 0 : qty;
          }

          byProductType.putIfAbsent(type, () => <String, dynamic>{
                'count': 0,
                'units': 0,
                'revenue': <String, double>{'NGN': 0.0, 'USD': 0.0},
              });

          final g = (byProductType[type] as Map).cast<String, dynamic>();
          if (success) g['count'] = (g['count'] as int) + 1;
          if (success && type.toLowerCase() == 'coupon') {
            g['units'] = (g['units'] as int) + (qty < 0 ? 0 : qty);
          }
          if (success) {
            final gRev = (g['revenue'] as Map).cast<String, dynamic>();
            gRev[currency] = _asDouble(gRev[currency]) + itAmount;
          }

          final dayTypes = (day['byProductType'] as Map).cast<String, dynamic>();
          dayTypes.putIfAbsent(type, () => <String, dynamic>{
                'count': 0,
                'units': 0,
                'revenue': <String, double>{'NGN': 0.0, 'USD': 0.0},
              });

          final dAgg = (dayTypes[type] as Map).cast<String, dynamic>();
          if (success) dAgg['count'] = (dAgg['count'] as int) + 1;
          if (success && type.toLowerCase() == 'coupon') {
            dAgg['units'] = (dAgg['units'] as int) + (qty < 0 ? 0 : qty);
          }
          if (success) {
            final dRev = (dAgg['revenue'] as Map).cast<String, dynamic>();
            dRev[currency] = _asDouble(dRev[currency]) + itAmount;
          }
        }
      }
    }

    // Success attempts
    Query<Map<String, dynamic>> successQ = _firestore
        .collection('payment_attempts')
        .where('status', isEqualTo: 'client_success')
        .where('createdAtMs', isGreaterThanOrEqualTo: fromMs)
        .orderBy('createdAtMs', descending: true)
        .limit(500);

    DocumentSnapshot<Map<String, dynamic>>? last;
    while (true) {
      Query<Map<String, dynamic>> page = successQ;
      if (last != null) page = page.startAfterDocument(last);

      final snap = await page.get(const GetOptions(source: Source.server)).timeout(const Duration(seconds: 20));
      if (snap.docs.isEmpty) break;

      await consume(snap.docs, success: true);
      last = snap.docs.last;
      if (snap.docs.length < 500) break;
    }

    // Failed attempts
    Query<Map<String, dynamic>> failedQ = _firestore
        .collection('payment_attempts')
        .where('status', whereIn: const ['cancelled', 'client_failed'])
        .where('createdAtMs', isGreaterThanOrEqualTo: fromMs)
        .orderBy('createdAtMs', descending: true)
        .limit(500);

    last = null;
    while (true) {
      Query<Map<String, dynamic>> page = failedQ;
      if (last != null) page = page.startAfterDocument(last);

      final snap = await page.get(const GetOptions(source: Source.server)).timeout(const Duration(seconds: 20));
      if (snap.docs.isEmpty) break;

      await consume(snap.docs, success: false);
      last = snap.docs.last;
      if (snap.docs.length < 500) break;
    }

    final updatedAtMs = _nowMs();
    final batch = _firestore.batch();

    batch.set(_firestore.collection('analytics_summary').doc('global'), <String, dynamic>{
      'updatedAtMs': updatedAtMs,
      'totals': <String, dynamic>{
        'successfulPayments': successfulPayments,
        'failedPayments': failedPayments,
        'couponsSold': couponsSold,
        'leaguesCreated': 0,
        'revenue': revenueTotals,
      },
      'byProductType': byProductType,
      'range': <String, dynamic>{'daysBack': daysBack, 'fromMs': fromMs},
      'source': 'payment_attempts',
    }, SetOptions(merge: true));

    for (final e in byDay.entries) {
      final dayRef = _firestore.collection('revenue_by_day').doc(e.key);
      final dayData = e.value..['updatedAtMs'] = updatedAtMs;
      batch.set(dayRef, dayData, SetOptions(merge: true));
    }

    await batch.commit().timeout(const Duration(seconds: 30));
  }
}
