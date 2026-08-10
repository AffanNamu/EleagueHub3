// lib/features/leagues/logic/league_premium_upgrade_helper.dart
//
// UPDATED: this file used to contain a full inline plan-purchase bottom
// sheet (_InlinePlanPurchaseSheet) that talked to GooglePlayBillingService
// and the Flutterwave payment service directly. That has been removed
// entirely. Every caller of LeaguePremiumUpgradeHelper.openUpgradeFlow()
// now gets routed to the single, dedicated payment surface:
// UpgradePlanScreen (lib/features/leagues/presentation/upgrade_plan_screen.dart).
//
// This file is kept only as a thin, backward-compatible wrapper so
// existing call sites don't need to change their call signature.

import 'package:flutter/material.dart';

import '../../master_leagues/domain/master_league_plan.dart';
import '../presentation/upgrade_plan_screen.dart';

class LeaguePremiumUpgradeHelper {
  const LeaguePremiumUpgradeHelper._();

  /// Opens the dedicated Upgrade Plan screen and returns true if the
  /// user's plan changed (a purchase completed successfully), false
  /// otherwise (cancelled, back button, or failure).
  ///
  /// [leagueName] is accepted for backward compatibility with existing
  /// call sites but is no longer shown anywhere — UpgradePlanScreen is
  /// a generic, account-level plan picker, not tied to a single league.
  /// [initialPlan] lets a caller pre-select a tab (e.g. suggest Pro
  /// when the user hit a Basic-tier limit).
  static Future<bool> openUpgradeFlow(
    BuildContext context, {
    String leagueName = 'Organizer Premium',
    MasterLeaguePlan? initialPlan,
  }) {
    return UpgradePlanScreen.open(context, initialPlan: initialPlan);
  }
}