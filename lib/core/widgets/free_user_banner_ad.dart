import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/plan_status_service.dart';
import 'app_banner_ad.dart';

/// Wraps [AppBannerAd] with the product policy for where it shows: never
/// for a signed-in user with an active Pro/Elite plan (the standard
/// "paying users don't see ads" rule), and shown by default otherwise --
/// including while the plan check is still in flight or fails, matching
/// the fail-open direction used everywhere else ads appear in this app
/// (see RewardedAdManager) so a transient Firestore hiccup never quietly
/// costs ad revenue from a free user for the rest of the session.
///
/// Extracted out of home_shell.dart's original private _HomeBannerAdSlot
/// so every screen that wants the same "free users only" banner (Home,
/// Fixtures, Standings, ...) shares one implementation instead of
/// re-checking plan status ad hoc.
class FreeUserBannerAd extends StatefulWidget {
  const FreeUserBannerAd({super.key});

  @override
  State<FreeUserBannerAd> createState() => _FreeUserBannerAdState();
}

class _FreeUserBannerAdState extends State<FreeUserBannerAd> {
  bool _hideForPaidPlan = false;

  @override
  void initState() {
    super.initState();
    // ignore: discarded_futures
    _checkPlan();
  }

  Future<void> _checkPlan() async {
    final uid = FirebaseAuth.instance.currentUser?.uid.trim() ?? '';
    if (uid.isEmpty) return;

    try {
      final paid = await PlanStatusService.instance.isPaidPlanActive(uid);
      if (mounted && paid) setState(() => _hideForPaidPlan = true);
    } catch (_) {
      // Fail open -- see class doc comment.
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_hideForPaidPlan) return const SizedBox.shrink();
    return const AppBannerAd();
  }
}
