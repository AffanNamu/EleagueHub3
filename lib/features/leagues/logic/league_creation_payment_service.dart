
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:uuid/uuid.dart';



final leagueCreationPaymentServiceProvider = Provider<LeagueCreationPaymentService>((ref) {

  return SimulatedLeagueCreationPaymentService();

});



class LeagueCreationPaymentResult {

  final bool success;

  final String? receiptId;

  final int paidAtMs;

  final String provider;

  final String? errorMessage;



  const LeagueCreationPaymentResult._({

    required this.success,

    required this.receiptId,

    required this.paidAtMs,

    required this.provider,

    required this.errorMessage,

  });



  factory LeagueCreationPaymentResult.paid({

    required String receiptId,

    required int paidAtMs,

    required String provider,

  }) {

    return LeagueCreationPaymentResult._(

      success: true,

      receiptId: receiptId,

      paidAtMs: paidAtMs,

      provider: provider,

      errorMessage: null,

    );

  }



  factory LeagueCreationPaymentResult.failed({

    required String provider,

    required String errorMessage,

  }) {

    return LeagueCreationPaymentResult._(

      success: false,

      receiptId: null,

      paidAtMs: 0,

      provider: provider,

      errorMessage: errorMessage,

    );

  }

}



abstract class LeagueCreationPaymentService {

  Future<LeagueCreationPaymentResult> collectLeagueCreationFee({

    required String userId,

    required String leagueName,

  });



  String get providerName;

}



class SimulatedLeagueCreationPaymentService implements LeagueCreationPaymentService {

  final Uuid _uuid = const Uuid();



  @override

  String get providerName => 'simulated';



  @override

  Future<LeagueCreationPaymentResult> collectLeagueCreationFee({

    required String userId,

    required String leagueName,

  }) async {

    await Future.delayed(const Duration(milliseconds: 700));

    final now = DateTime.now().millisecondsSinceEpoch;

    final receiptId = 'SIM-CRT-${_uuid.v4()}';



    return LeagueCreationPaymentResult.paid(

      receiptId: receiptId,

      paidAtMs: now,

      provider: providerName,

    );

  }

}

