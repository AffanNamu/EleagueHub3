import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/locale/app_localizations.dart';
import '../../../core/persistence/prefs_service.dart';
import '../../../core/routing/league_mode_provider.dart';
import '../../../core/theme/theme_controller.dart';
import '../../../core/widgets/glass.dart';
import '../../../core/widgets/glass_scaffold.dart';
import '../../../core/widgets/league_switcher.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/services/app_admins_service.dart';
import '../../auth/data/auth_service.dart';
import '../../auth/data/user_profile_repository.dart';
import '../../auth/models/user_profile.dart';
import '../../leagues/logic/coupon_config_service.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  String _couponLeagueSubtitle({
    required bool enabled,
    required int discountPercent,
  }) {
    if (!enabled || discountPercent <= 0) return 'Not enabled';
    return 'Users pay $discountPercent%';
  }

  void _showCouponConfigSheet(
    BuildContext context, {
    required String leagueId,
    required String leagueName,
  }) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        final cs = theme.colorScheme;
        final onSurface = cs.onSurface;

        final cfgStream = CouponConfigService().watchConfig(leagueId);
        final redemptionsQuery = FirebaseFirestore.instance
            .collection('leagues')
            .doc(leagueId)
            .collection('couponRedemptions')
            .orderBy('paidAtMs', descending: true)
            .limit(150);

        String money(double v) {
          final r = double.parse(v.toStringAsFixed(2));
          final i = r.toInt();
          if ((r - i).abs() < 0.000001) return '$i';
          return r.toStringAsFixed(2);
        }

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 620),
                child: Glass(
                  borderRadius: 28,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Coupons',
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: onSurface,
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          leagueName,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: onSurface.withOpacity(0.70),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                        StreamBuilder<CouponConfig?>(
                          stream: cfgStream,
                          builder: (context, snap) {
                            if (snap.hasError) {
                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                child: Text(
                                  'Failed to load coupon configuration.',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: cs.error,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              );
                            }
                            if (!snap.hasData) {
                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                child: Center(child: CircularProgressIndicator(color: cs.primary)),
                              );
                            }
                            final cfg = snap.data;
                            if (cfg == null) {
                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                child: Column(
                                  children: [
                                    Text(
                                      'No coupon configuration yet.',
                                      style: theme.textTheme.bodySmall?.copyWith(
                                        color: onSurface.withOpacity(0.70),
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    FilledButton.icon(
                                      onPressed: () => Navigator.of(ctx).pop(),
                                      icon: const Icon(Icons.check),
                                      label: const Text('Close'),
                                    ),
                                  ],
                                ),
                              );
                            }

                            final redeemed = cfg.qtyRedeemed;

                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _kv(context, 'Currency', cfg.currency),
                                _kv(context, 'Unit price', '${money(cfg.unitPrice)} ${cfg.currency}'),
                                _kv(context, 'Effective unit', '${money(cfg.effectiveUnit)} ${cfg.currency}'),
                                _kv(context, 'Threshold',
                                    cfg.threshold == null ? '—' : '${money(cfg.threshold!)} ${cfg.currency}'),
                                _kv(context, 'Threshold discount', '${money(cfg.thresholdDiscountPercent)}%'),
                                const Divider(),
                                _kv(context, 'Users pay', '${cfg.userPaysPercent}%'),
                                _kv(context, 'Admin pays', '${cfg.organizerPaysPercent}%'),
                                const Divider(),
                                _kv(context, 'Purchased (total)', '${cfg.qtyTotal}'),
                                _kv(context, 'Remaining', '${cfg.qtyRemaining}'),
                                _kv(context, 'Redeemed', '$redeemed'),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Expanded(
                                      child: OutlinedButton.icon(
                                        onPressed: () => Navigator.of(ctx).pop(),
                                        icon: const Icon(Icons.close),
                                        label: const Text('Close'),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: FilledButton.icon(
                                        onPressed: () {
                                          Navigator.of(ctx).pop();
                                          // Open upgrade/payment to buy more or adjust subsidy
                                          GoRouter.of(context).push('/leagues/$leagueId/upgrade/payment', extra: {
                                            'leagueId': leagueId,
                                            'leagueName': leagueName,
                                            'addonsOnly': true,
                                            'existingCouponsEnabled': true,
                                            'existingCouponCount': cfg.qtyRemaining,
                                            'existingCouponDiscountPercent': cfg.userPaysPercent,
                                          });
                                        },
                                        icon: const Icon(Icons.add_shopping_cart),
                                        label: const Text('Buy more / adjust'),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 14),
                                Text(
                                  'Recent redemptions',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: onSurface,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                ConstrainedBox(
                                  constraints: const BoxConstraints(maxHeight: 320),
                                  child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                                    stream: redemptionsQuery.snapshots(),
                                    builder: (context, rs) {
                                      if (rs.hasError) {
                                        return Center(
                                          child: Text(
                                            'Failed to load redemptions.',
                                            style: theme.textTheme.bodySmall?.copyWith(
                                              color: cs.error,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        );
                                      }
                                      if (!rs.hasData) {
                                        return Center(child: CircularProgressIndicator(color: cs.primary));
                                      }
                                      final docs = rs.data!.docs;
                                      if (docs.isEmpty) {
                                        return Center(
                                          child: Text(
                                            'No redemptions yet.',
                                            style: theme.textTheme.bodySmall?.copyWith(
                                              color: onSurface.withOpacity(0.70),
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        );
                                      }
                                      return ListView.separated(
                                        itemCount: docs.length,
                                        separatorBuilder: (_, __) => Divider(color: onSurface.withOpacity(0.10)),
                                        itemBuilder: (context, i) {
                                          final d = docs[i].data();
                                          final userId = (d['userId'] as String?) ?? '';
                                          final status = (d['status'] as String?) ?? 'pending';
                                          final paidAtMs = (d['paidAtMs'] as num?)?.toInt() ?? 0;
                                          final provider = (d['provider'] as String?) ?? '';
                                          final expected = (d['expectedAmount'] as num?)?.toDouble() ?? 0.0;
                                          final currency = (d['currency'] as String?) ?? cfg.currency;

                                          final isPaid = status == 'paid';
                                          final when = paidAtMs > 0
                                              ? DateTime.fromMillisecondsSinceEpoch(paidAtMs).toLocal().toString()
                                              : '—';

                                          return ListTile(
                                            dense: true,
                                            contentPadding: EdgeInsets.zero,
                                            leading: Icon(
                                              isPaid ? Icons.verified : Icons.pending,
                                              color: isPaid ? const Color(0xFF22C55E) : cs.primary,
                                              size: 20,
                                            ),
                                            title: Text(
                                              userId.isEmpty
                                                  ? '(unknown user)'
                                                  : (userId.length > 12 ? '${userId.substring(0, 12)}…' : userId),
                                              style: theme.textTheme.bodyMedium?.copyWith(
                                                color: onSurface,
                                                fontWeight: FontWeight.w900,
                                              ),
                                            ),
                                            subtitle: Text(
                                              isPaid
                                                  ? 'Paid • $provider • $when'
                                                  : 'Pending • ${money(expected)} $currency',
                                              style: theme.textTheme.bodySmall?.copyWith(
                                                color: onSurface.withOpacity(0.65),
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                            trailing: IconButton(
                                              tooltip: 'Copy user id',
                                              icon: Icon(Icons.copy, color: onSurface.withOpacity(0.72), size: 18),
                                              onPressed: () async {
                                                await Clipboard.setData(ClipboardData(text: userId));
                                                if (!context.mounted) return;
                                                ScaffoldMessenger.of(context).showSnackBar(
                                                  SnackBar(content: Text('Copied: $userId')),
                                                );
                                              },
                                            ),
                                          );
                                        },
                                      );
                                    },
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Ensure dynamic admins watcher runs (safe if called multiple times).
    AppAdminsService.instance.ensureStarted();

    final l10n = context.l10n;
    final theme = Theme.of(context);
    final t = theme.textTheme;
    final onBg = theme.colorScheme.onBackground;
    final onSurface = theme.colorScheme.onSurface;

    final themeState = ref.watch(themeControllerProvider);
    final currentLeague = ref.watch(leagueModeProvider);

    final user = FirebaseAuth.instance.currentUser;
    final uid = user?.uid ?? '';

    final isPricingAdmin = AppAdminsService.instance.isPricingAdminUid(uid);

    final repo = UserProfileRepository();

    return GlassScaffold(
      body: ListView(
        padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 16, 24),
        children: [
          const SizedBox(height: 56),
          Text(
            l10n.tr('profile_title'),
            style: t.headlineSmall?.copyWith(
              color: onBg.withOpacity(0.95),
              fontWeight: FontWeight.w900,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            l10n.tr('profile_subtitle'),
            style: t.bodySmall?.copyWith(color: onBg.withOpacity(0.70)),
          ),
          const SizedBox(height: 16),

          /// USER CARD
          Glass(
            padding: const EdgeInsets.all(14),
            child: StreamBuilder<UserProfile?>(
              stream: uid.isEmpty ? const Stream<UserProfile?>.empty() : repo.watchByUserId(uid),
              builder: (context, snap) {
                final profile = snap.data;

                final teamName = (profile != null && profile.teamName.trim().isNotEmpty)
                    ? profile.teamName.trim()
                    : (user?.displayName ?? l10n.tr('profile_team_placeholder'));

                final shortUserId = (profile != null)
                    ? profile.effectiveShareId
                    : (uid.isEmpty ? '' : UserProfile.deriveShareIdFromUid(uid));

                final iconMuted = onSurface.withOpacity(0.72);
                final iconDim = onSurface.withOpacity(0.55);

                return Row(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Theme.of(context).colorScheme.primary.withOpacity(0.35),
                            blurRadius: 18,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: CircleAvatar(
                        radius: 28,
                        backgroundColor: Theme.of(context).colorScheme.primary.withOpacity(0.85),
                        child: const Icon(Icons.person, color: Colors.white, size: 28),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 200),
                                  child: Text(
                                    teamName,
                                    key: ValueKey(teamName),
                                    style: t.titleLarge?.copyWith(
                                      fontWeight: FontWeight.w900,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                              IconButton(
                                tooltip: l10n.tr('profile_edit_team_name_tooltip'),
                                icon: Icon(Icons.edit, color: iconMuted, size: 18),
                                onPressed: uid.isEmpty
                                    ? null
                                    : () {
                                        HapticFeedback.selectionClick();
                                        _editTeamName(
                                          context,
                                          userId: uid,
                                          current: profile?.teamName ?? '',
                                        );
                                      },
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  uid.isEmpty
                                      ? l10n.tr('profile_not_signed_in')
                                      : '${l10n.tr('profile_userid_prefix')} $shortUserId',
                                  style: t.bodySmall?.copyWith(
                                    color: onSurface.withOpacity(0.72),
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              IconButton(
                                tooltip: l10n.tr('profile_copy_userid_tooltip'),
                                icon: Icon(Icons.copy, color: iconDim, size: 18),
                                onPressed: uid.isEmpty
                                    ? null
                                    : () async {
                                        HapticFeedback.lightImpact();
                                        await Clipboard.setData(ClipboardData(text: shortUserId));
                                        if (!context.mounted) return;
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(content: Text(l10n.tr('profile_userid_copied'))),
                                        );
                                      },
                              ),
                            ],
                          ),
                          if (uid.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              '${l10n.tr('profile_internal_uid_debug_prefix')} ${uid.length > 10 ? '${uid.substring(0, 10)}…' : uid}',
                              style: t.bodySmall?.copyWith(
                                color: onSurface.withOpacity(0.45),
                                fontSize: 10,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ],
                      ),
                    ),

                    /// THEME TOGGLE
                    IconButton(
                      tooltip: l10n.tr('profile_toggle_theme_tooltip'),
                      icon: Icon(
                        themeState.mode == ThemeMode.dark ? Icons.light_mode : Icons.dark_mode,
                        color: theme.colorScheme.primary,
                      ),
                      onPressed: () {
                        HapticFeedback.selectionClick();
                        ref.read(themeControllerProvider.notifier).toggleTheme();
                      },
                    ),

                    /// LOGOUT (WITH GLASS WARNING)
                    IconButton(
                      tooltip: l10n.tr('profile_logout_tooltip'),
                      icon: Icon(Icons.logout, color: iconMuted),
                      onPressed: () async {
                        final ok = await _confirmLogout(context);
                        if (!ok) return;

                        // --- DO NOT CHANGE LOGIC BELOW ---
                        final prefs = ref.read(prefsServiceProvider);
                        await AuthService().signOut();
                        await prefs.clearCurrentUserId();
                        if (!context.mounted) return;
                        context.go('/login');
                      },
                    ),
                  ],
                );
              },
            ),
          ),

          const SizedBox(height: 22),

          /// LEAGUE MODE SWITCHER (APP STANDARD)
          const LeagueSwitcher(),

          const SizedBox(height: 22),

          /// STATS
          SectionHeader(l10n.tr('profile_section_league_overview')),
          const SizedBox(height: 12),

          Glass(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(child: _Stat(label: l10n.tr('profile_stat_active'), value: '2')),
                const SizedBox(width: 12),
                Expanded(child: _Stat(label: l10n.tr('profile_stat_teams'), value: '16')),
                const SizedBox(width: 12),
                Expanded(
                  child: _Stat(
                    label: l10n.tr('profile_stat_format'),
                    value: currentLeague.name.toUpperCase().replaceAll('CLASSIC', 'CL').replaceAll('SWISS', 'SW'),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 22),

          /// COUPONS (organizer)
          SectionHeader('Coupons'),
          const SizedBox(height: 12),
          if (uid.isEmpty)
            Glass(
              padding: const EdgeInsets.all(14),
              child: Text(
                'Sign in to view your coupons.',
                style: t.bodyMedium?.copyWith(
                  color: onSurface.withOpacity(0.72),
                  fontWeight: FontWeight.w600,
                ),
              ),
            )
          else
            Glass(
              padding: const EdgeInsets.all(14),
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: FirebaseFirestore.instance
                    .collection('leagues')
                    .where('organizerUserId', isEqualTo: uid)
                    .limit(25)
                    .snapshots(),
                builder: (context, snap) {
                  if (snap.hasError) {
                    return Text(
                      'Failed to load coupons.',
                      style: t.bodyMedium?.copyWith(
                        color: theme.colorScheme.error,
                        fontWeight: FontWeight.w700,
                      ),
                    );
                  }

                  if (!snap.hasData) {
                    return Center(child: CircularProgressIndicator(color: theme.colorScheme.primary));
                  }

                  final leagues = snap.data!.docs
                      .map((d) => <String, dynamic>{...d.data(), 'id': d.id})
                      .where((m) =>
                          (m['couponsEnabled'] == true || m['couponsEnabled'] == 1) &&
                          ((m['couponDiscountPercent'] as num?)?.toInt() ?? 0) >= 0)
                      .toList();

                  if (leagues.isEmpty) {
                    return Text(
                      'No coupons found. Enable coupons during league creation payment.',
                      style: t.bodyMedium?.copyWith(
                        color: onSurface.withOpacity(0.72),
                        fontWeight: FontWeight.w600,
                      ),
                    );
                  }

                  return Column(
                    children: [
                      for (final m in leagues) ...[
                        _OrganizerLeagueCouponsTile(
                          leagueName: (m['name'] as String?) ?? 'League',
                          subtitle: _couponLeagueSubtitle(
                            enabled: true,
                            discountPercent: ((m['couponDiscountPercent'] as num?)?.toInt() ?? 0),
                          ),
                          onView: () => _showCouponConfigSheet(
                            context,
                            leagueId: (m['id'] as String?) ?? '',
                            leagueName: (m['name'] as String?) ?? 'League',
                          ),
                        ),
                        const SizedBox(height: 10),
                      ],
                    ],
                  );
                },
              ),
            ),

          const SizedBox(height: 22),

          /// PRICING ADMIN (owner/dynamic-admin only)
          if (isPricingAdmin) ...[
            SectionHeader('Admin'),
            const SizedBox(height: 12),
            Glass(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Icon(Icons.admin_panel_settings, color: theme.colorScheme.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Pricing Admin',
                      style: t.bodyMedium?.copyWith(
                        color: onSurface,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  FilledButton(
                    onPressed: () => GoRouter.of(context).push('/admin/pricing'),
                    child: const Text('Open'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Glass(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Icon(Icons.group_add, color: theme.colorScheme.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Manage pricing admins',
                      style: t.bodyMedium?.copyWith(
                        color: onSurface,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  FilledButton(
                    onPressed: () => GoRouter.of(context).push('/admin/pricing-admins'),
                    child: const Text('Open'),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _kv(BuildContext context, String k, String v) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
            width: 170,
            child: Text(
              k,
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurface.withOpacity(0.70),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: Text(
              v,
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurface.withOpacity(0.90),
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<bool> _confirmLogout(BuildContext context) async {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final t = theme.textTheme;
    final onSurface = theme.colorScheme.onSurface;

    final res = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withOpacity(0.55),
      builder: (ctx) {
        final dialogTheme = Theme.of(ctx);
        final dialogOnSurface = dialogTheme.colorScheme.onSurface;

        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
          child: Glass(
            padding: const EdgeInsets.all(16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Colors.amber.withOpacity(0.14),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.amber.withOpacity(0.35)),
                        ),
                        child: const Icon(Icons.warning_amber_rounded, color: Colors.amber),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          l10n.tr('profile_logout_dialog_title'),
                          style: t.titleLarge?.copyWith(
                            color: dialogOnSurface,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: l10n.tr('profile_close_tooltip'),
                        onPressed: () => Navigator.of(ctx).pop(false),
                        icon: Icon(Icons.close, color: dialogOnSurface.withOpacity(0.72)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(
                      l10n.tr('profile_logout_dialog_message'),
                      style: t.bodyMedium?.copyWith(
                        color: dialogOnSurface.withOpacity(0.72),
                        height: 1.35,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: dialogOnSurface.withOpacity(0.80),
                            side: BorderSide(color: dialogOnSurface.withOpacity(0.18)),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          onPressed: () => Navigator.of(ctx).pop(false),
                          child: Text(l10n.tr('common_cancel')),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFFE53935),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          onPressed: () => Navigator.of(ctx).pop(true),
                          child: Text(l10n.tr('profile_logout_button')),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    return res ?? false;
  }

  Future<void> _editTeamName(
    BuildContext context, {
    required String userId,
    required String current,
  }) async {
    final l10n = context.l10n;

    final controller = TextEditingController(text: current);
    final repo = UserProfileRepository();

    try {
      final next = await showDialog<String?>(
        context: context,
        builder: (ctx) {
          final theme = Theme.of(ctx);
          final onSurface = theme.colorScheme.onSurface;

          return AlertDialog(
            backgroundColor: theme.colorScheme.surface,
            title: Text(
              l10n.tr('profile_edit_team_dialog_title'),
              style: TextStyle(
                color: onSurface,
                fontWeight: FontWeight.bold,
              ),
            ),
            content: TextField(
              controller: controller,
              autofocus: true,
              style: TextStyle(color: onSurface, fontWeight: FontWeight.w600),
              decoration: InputDecoration(
                hintText: l10n.tr('profile_team_name_hint'),
                hintStyle: TextStyle(color: onSurface.withOpacity(0.45)),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(null),
                child: Text(l10n.tr('common_cancel')),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
                child: Text(l10n.tr('common_save')),
              ),
            ],
          );
        },
      );

      if (next == null) return;
      if (next.isEmpty) return;

      await repo.updateTeamName(userId: userId, teamName: next);

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.tr('profile_team_name_updated'))),
      );
    } finally {
      controller.dispose();
    }
  }
}

class _OrganizerLeagueCouponsTile extends StatelessWidget {
  const _OrganizerLeagueCouponsTile({
    required this.leagueName,
    required this.subtitle,
    required this.onView,
  });

  final String leagueName;
  final String subtitle;
  final VoidCallback onView;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Glass(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          Icon(Icons.emoji_events_outlined, color: cs.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  leagueName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: cs.onSurface,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurface.withOpacity(0.65),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          FilledButton(
            onPressed: onView,
            child: const Text('View'),
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = theme.textTheme;
    final onSurface = theme.colorScheme.onSurface;

    return Glass(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          FittedBox(
            child: Text(
              value,
              style: t.titleLarge?.copyWith(
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: t.bodySmall?.copyWith(color: onSurface.withOpacity(0.65)),
            maxLines: 1,
          ),
        ],
      ),
    );
  }
}
