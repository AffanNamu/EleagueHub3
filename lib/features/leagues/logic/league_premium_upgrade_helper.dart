import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'league_creation_payment_service.dart';

class LeaguePremiumUpgradeHelper {
  const LeaguePremiumUpgradeHelper._();

  static Future<LeagueCreationPaymentResult?> openUpgradeFlow(
    BuildContext context, {
    String leagueName = 'Organizer Premium',
  }) async {
    return await context.push<LeagueCreationPaymentResult?>(
      '/leagues/create/payment',
      extra: <String, dynamic>{
        'premiumUpgrade': true,
        'leagueName': leagueName,
      },
    );
  }
}
