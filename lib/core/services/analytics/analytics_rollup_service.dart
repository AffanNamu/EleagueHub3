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

  /// Rebuilds analytics_summary/global and revenue_by_day for the last [daysBack] days
  /// by scanning successful payments.
  Future<void> rebuild({int daysBack = 30}) async {
    final now = DateTime.now().toUtc();
    final from = now.subtract(Duration(days: daysBack));
    final fromMs = from.millisecondsSinceEpoch;

    // Fetch payments in pages
    Query<Map<String, dynamic>> q = _firestore
        .collection('payments')
        .where('status', isEqualTo: 'success')
        .where('paidAtMs', isGreaterThanOrEqualTo: fromMs)
        .orderBy('paidAtMs', descending: true)
        .limit(500);

    int successfulPayments = 0;
    int couponsSold = 0;

    final revenueTotals = <String, double>{'NGN': 0, 'USD': 0};
    final byProductType = <String, dynamic>{};

    final byDay = <String, Map<String, dynamic>>{};

    DocumentSnapshot<Map<String, dynamic>>? last;
    while (true) {
      Query<Map<String, dynamic>> page = q;
      if (last != null) page = page.startAfterDocument(last);

      final snap = await page.get(const GetOptions(source: Source.server)).timeout(const Duration(seconds: 20));
      if (snap.docs.isEmpty) break;

      for (final doc in snap.docs) {
        final data = doc.data();
        successfulPayments++;

        final currency = (data['currency'] ?? 'USD').toString().trim().toUpperCase();
        final amount = (data['amount'] is num) ? (data['amount'] as num).toDouble() : 0.0;
        revenueTotals[currency] = (revenueTotals[currency] ?? 0) + amount;

        final paidAtMs = (data['paidAtMs'] is num) ? (data['paidAtMs'] as num).toInt() : 0;
        final dayId = _dayIdUtcFromMs(paidAtMs > 0 ? paidAtMs : _nowMs());

        byDay.putIfAbsent(dayId, () {
          return <String, dynamic>{
            'dayId': dayId,
            'successfulPayments': 0,
            'failedPayments': 0,
            'leaguesCreated': 0,
            'revenue': <String, double>{'NGN': 0, 'USD': 0},
            'byProductType': <String, dynamic>{},
          };
        });

        final day = byDay[dayId]!;
        day['successfulPayments'] = (day['successfulPayments'] as int) + 1;
        final dayRevenue = (day['revenue'] as Map).cast<String, dynamic>();
        dayRevenue[currency] = ((dayRevenue[currency] is num) ? (dayRevenue[currency] as num).toDouble() : 0.0) + amount;

        // items[] => byProductType + couponsSold
        final items = (data['items'] is List) ? (data['items'] as List) : const [];
        for (final it in items) {
          if (it is! Map) continue;
          final m = it.cast<String, dynamic>();
          final type = (m['productType'] ?? '').toString().trim();
          if (type.isEmpty) continue;

          final itAmount = (m['amount'] is num) ? (m['amount'] as num).toDouble() : 0.0;
          final qty = (m['quantity'] is num) ? (m['quantity'] as num).toInt() : 0;

          // coupons sold
          if (type.toLowerCase() == 'coupon') {
            couponsSold += qty < 0 ? 0 : qty;
          }

          // global byProductType
          byProductType.putIfAbsent(type, () => <String, dynamic>{
                'count': 0,
                'units': 0,
                'revenue': <String, double>{'NGN': 0, 'USD': 0},
              });

          final g = (byProductType[type] as Map).cast<String, dynamic>();
          g['count'] = (g['count'] as int) + 1;
          if (type.toLowerCase() == 'coupon') {
            g['units'] = (g['units'] as int) + (qty < 0 ? 0 : qty);
          }
          final gRev = (g['revenue'] as Map).cast<String, dynamic>();
          gRev[currency] = ((gRev[currency] is num) ? (gRev[currency] as num).toDouble() : 0.0) + itAmount;

          // day byProductType
          final dayTypes = (day['byProductType'] as Map).cast<String, dynamic>();
          dayTypes.putIfAbsent(type, () => <String, dynamic>{
                'count': 0,
                'units': 0,
                'revenue': <String, double>{'NGN': 0, 'USD': 0},
              });

          final dAgg = (dayTypes[type] as Map).cast<String, dynamic>();
          dAgg['count'] = (dAgg['count'] as int) + 1;
          if (type.toLowerCase() == 'coupon') {
            dAgg['units'] = (dAgg['units'] as int) + (qty < 0 ? 0 : qty);
          }
          final dRev = (dAgg['revenue'] as Map).cast<String, dynamic>();
          dRev[currency] = ((dRev[currency] is num) ? (dRev[currency] as num).toDouble() : 0.0) + itAmount;
        }
      }

      last = snap.docs.last;
      if (snap.docs.length < 500) break;
    }

    final updatedAtMs = _nowMs();

    // Write summary + days (admin-only via rules)
    final batch = _firestore.batch();

    final summaryRef = _firestore.collection('analytics_summary').doc('global');
    batch.set(summaryRef, <String, dynamic>{
      'updatedAtMs': updatedAtMs,
      'totals': <String, dynamic>{
        'successfulPayments': successfulPayments,
        'failedPayments': 0, // optional: you can compute from payment_attempts if needed
        'couponsSold': couponsSold,
        'leaguesCreated': 0,
        'revenue': revenueTotals,
      },
      'byProductType': byProductType,
      'range': <String, dynamic>{
        'daysBack': daysBack,
        'fromMs': fromMs,
      },
    }, SetOptions(merge: true));

    // Upsert each day doc
    for (final e in byDay.entries) {
      final dayRef = _firestore.collection('revenue_by_day').doc(e.key);
      final dayData = e.value;
      dayData['updatedAtMs'] = updatedAtMs;
      batch.set(dayRef, dayData, SetOptions(merge: true));
    }

    await batch.commit().timeout(const Duration(seconds: 30));
  }
}
