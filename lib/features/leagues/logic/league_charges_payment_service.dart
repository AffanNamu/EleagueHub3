import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

final leagueChargesPaymentServiceProvider = Provider<LeagueChargesPaymentService>((ref) {
  return SimulatedLeagueChargesPaymentService();
});

class LeagueChargesPaymentResult {
  final bool success;
  final String? receiptId;
  final int paidAtMs;
  final String provider;
  final String? errorMessage;

  const LeagueChargesPaymentResult._({
    required this.success,
    required this.receiptId,
    required this.paidAtMs,
    required this.provider,
    required this.errorMessage,
  });

  factory LeagueChargesPaymentResult.paid({
    required String receiptId,
    required int paidAtMs,
    required String provider,
  }) {
    return LeagueChargesPaymentResult._(
      success: true,
      receiptId: receiptId,
      paidAtMs: paidAtMs,
      provider: provider,
      errorMessage: null,
    );
  }

  factory LeagueChargesPaymentResult.failed({
    required String provider,
    required String errorMessage,
  }) {
    return LeagueChargesPaymentResult._(
      success: false,
      receiptId: null,
      paidAtMs: 0,
      provider: provider,
      errorMessage: errorMessage,
    );
  }
}

abstract class LeagueChargesPaymentService {
  Future<LeagueChargesPaymentResult> payLeagueCharges({
    required String userId,
    required String leagueId,
    required String leagueName,
  });

  String get providerName;
}

class SimulatedLeagueChargesPaymentService implements LeagueChargesPaymentService {
  final Uuid _uuid = const Uuid();

  @override
  String get providerName => 'simulated';

  @override
  Future<LeagueChargesPaymentResult> payLeagueCharges({
    required String userId,
    required String leagueId,
    required String leagueName,
  }) async {
    await Future.delayed(const Duration(milliseconds: 700));
    final now = DateTime.now().millisecondsSinceEpoch;
    final receiptId = 'SIM-CHG-${_uuid.v4()}';

    return LeagueChargesPaymentResult.paid(
      receiptId: receiptId,
      paidAtMs: now,
      provider: providerName,
    );
  }
}
