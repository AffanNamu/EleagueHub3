import 'dart:convert';

import '../../../core/persistence/prefs_service.dart';

class LeagueChargesReceipt {
  final String leagueId;
  final String userId;
  final String receiptId;
  final String provider;
  final int paidAtMs;

  const LeagueChargesReceipt({
    required this.leagueId,
    required this.userId,
    required this.receiptId,
    required this.provider,
    required this.paidAtMs,
  });

  Map<String, dynamic> toMap() => {
        'leagueId': leagueId,
        'userId': userId,
        'receiptId': receiptId,
        'provider': provider,
        'paidAtMs': paidAtMs,
      };

  factory LeagueChargesReceipt.fromMap(Map<String, dynamic> map) {
    return LeagueChargesReceipt(
      leagueId: (map['leagueId'] as String?) ?? '',
      userId: (map['userId'] as String?) ?? '',
      receiptId: (map['receiptId'] as String?) ?? '',
      provider: (map['provider'] as String?) ?? '',
      paidAtMs: (map['paidAtMs'] as num?)?.toInt() ?? 0,
    );
  }
}

class LeagueChargesStore {
  LeagueChargesStore(this._prefs);
  final PreferencesService _prefs;

  String _key({
    required String userId,
    required String leagueId,
  }) =>
      'league_charges_receipt.$userId.$leagueId';

  bool hasPaidCharges({
    required String userId,
    required String leagueId,
  }) {
    final raw = _prefs.getString(_key(userId: userId, leagueId: leagueId));
    return raw != null && raw.trim().isNotEmpty;
  }

  LeagueChargesReceipt? getReceipt({
    required String userId,
    required String leagueId,
  }) {
    final raw = _prefs.getString(_key(userId: userId, leagueId: leagueId));
    if (raw == null || raw.trim().isEmpty) return null;

    try {
      final map = (jsonDecode(raw) as Map).cast<String, dynamic>();
      return LeagueChargesReceipt.fromMap(map);
    } catch (_) {
      return null;
    }
  }

  Future<void> storeReceipt(LeagueChargesReceipt receipt) async {
    final raw = jsonEncode(receipt.toMap());
    await _prefs.setString(
      _key(userId: receipt.userId, leagueId: receipt.leagueId),
      raw,
    );
  }
}
