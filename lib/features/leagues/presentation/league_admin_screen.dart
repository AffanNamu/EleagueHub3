import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../../core/errors/user_friendly_error.dart';
import '../../../core/locale/app_localizations.dart';
import '../../../core/persistence/prefs_service.dart';
import '../../../core/services/connectivity_service.dart'
    hide UserFriendlyException;
import '../../../core/services/notification_service.dart';
import '../../../core/services/remote_pricing_service.dart';
import '../../../core/widgets/glass.dart';
import '../../../core/widgets/glass_scaffold.dart';
import '../../auth/data/user_profile_repository.dart'
    hide UserFriendlyException;
import '../data/league_spaces_local.dart' hide UserFriendlyException;
import '../data/leagues_repository_local.dart' hide UserFriendlyException;
import '../logic/coupon_codes_service.dart';
import '../logic/coupon_config_service.dart' hide UserFriendlyException;
import '../logic/league_creation_payment_service.dart';
import '../logic/league_media_service.dart';
import '../models/league.dart';
import '../models/league_announcement.dart';
import '../models/league_format.dart';
import '../models/league_space.dart';
import '../models/team.dart';
import 'add_teams_screen.dart';
import 'league_participants_screen.dart';
import 'utils/roster_csv_exporter.dart';

class LeagueAdminScreen extends ConsumerStatefulWidget {
  final bool hasPendingChanges;
  final String leagueId;

  const LeagueAdminScreen({
    super.key,
    this.hasPendingChanges = true,
    required this.leagueId,
  });

  @override
  ConsumerState<LeagueAdminScreen> createState() => _LeagueAdminScreenState();
}

class _LeagueAdminScreenState extends ConsumerState<LeagueAdminScreen> {
  late final LocalLeaguesRepository _repo;
  late final LeagueSpacesFirebase _spaceRepo;

  League? _league;
  LeagueSpace? _space;

  bool _isLeagueLoading = true;
  bool _exportingRoster = false;

  bool _showAddMeAsParticipant = false;
  bool _addingMeAsParticipant = false;

  bool _processingUpgradePayment = false;

  String _currentAuthUid = '';
  String _remoteOrganizerUid = '';
  String _remoteOwnerUid = '';

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final Uuid _uuid = const Uuid();

  static const List<String> _groupNames = <String>[
    'Group A',
    'Group B',
    'Group C',
    'Group D',
    'Group E',
    'Group F',
    'Group G',
    'Group H',
  ];

  bool _looksLikeFirebaseUid(String s) => s.trim().length > 20;

  void _snack(String msg) {
    if (!mounted) return;
    final trimmed = msg.trim();
    if (trimmed.isEmpty) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(trimmed), behavior: SnackBarBehavior.floating),
    );
  }

  String? _authUidOrRedirect() {
    final uid = (FirebaseAuth.instance.currentUser?.uid ?? '').trim();
    if (uid.isEmpty) {
      if (mounted) context.go('/login');
      return null;
    }
    return uid;
  }

  Future<void> _requireOnline() async {
    await ConnectivityService.instance.requireOnline(
      timeout: const Duration(seconds: 4),
    );
  }

  bool _isRulesOwnerForLeague(
    League league, {
    required String authUid,
    required String remoteOrganizerUid,
    required String remoteOwnerUid,
  }) {
    final a = authUid.trim();
    if (a.isEmpty) return false;

    final ro = remoteOrganizerUid.trim();
    final rw = remoteOwnerUid.trim();
    if (ro.isNotEmpty || rw.isNotEmpty) {
      return ro == a || rw == a;
    }

    final ou = league.organizerUid.trim();
    if (ou.isNotEmpty) return ou == a;

    final legacy = league.organizerUserId.trim();
    return _looksLikeFirebaseUid(legacy) && legacy == a;
  }

  bool _canManageCoupons(League league) {
    final auth = _currentAuthUid.trim();
    if (auth.isEmpty) return false;
    final ro = _remoteOrganizerUid.trim();
    final rw = _remoteOwnerUid.trim();
    if (ro.isEmpty && rw.isEmpty) return false;
    return ro == auth || rw == auth;
  }

  String _couponSubtitleFromLeague(League league) {
    if (!league.couponsEnabled) return 'Not enabled';
    final pct = league.couponDiscountPercent;
    final qty = league.couponCount;
    return 'Discount $pct% • Purchased: $qty';
  }

  String _groupDisplayName(AppLocalizations l10n, String groupId) {
    final g = groupId.trim();
    if (g == 'Group A') return l10n.tr('add_teams_group_a');
    if (g == 'Group B') return l10n.tr('add_teams_group_b');
    if (g == 'Group C') return l10n.tr('add_teams_group_c');
    if (g == 'Group D') return l10n.tr('add_teams_group_d');
    if (g == 'Group E') return l10n.tr('add_teams_group_e');
    if (g == 'Group F') return l10n.tr('add_teams_group_f');
    if (g == 'Group G') return l10n.tr('add_teams_group_g');
    if (g == 'Group H') return l10n.tr('add_teams_group_h');
    return g;
  }

  List<String> _allowedGroupsForUclGroup(League league) {
    final max = league.maxTeams;
    if (max == 16) return _groupNames.take(4).toList();
    return _groupNames.take(8).toList();
  }

  String? _pickGroupWithSpace({
    required List<Team> teams,
    required List<String> allowedGroups,
  }) {
    final counts = <String, int>{for (final g in allowedGroups) g: 0};
    for (final t in teams) {
      final g = (t.groupId ?? '').trim();
      if (counts.containsKey(g)) counts[g] = (counts[g] ?? 0) + 1;
    }
    final available = counts.entries.where((e) => e.value < 4).toList();
    if (available.isEmpty) return null;
    available.sort((a, b) => a.value.compareTo(b.value));
    final min = available.first.value;
    final minGroups =
        available.where((e) => e.value == min).map((e) => e.key).toList();
    final rnd = Random.secure();
    return minGroups[rnd.nextInt(minGroups.length)];
  }

  @override
  void initState() {
    super.initState();
    final prefs = ref.read(prefsServiceProvider);
    _repo = LocalLeaguesRepository(prefs);
    _spaceRepo = LeagueSpacesFirebase(prefs);
    // ignore: discarded_futures
    _loadLeague();
  }

  Future<void> _loadLeague() async {
    setState(() => _isLeagueLoading = true);

    League? league;
    LeagueSpace? space;
    bool showAddMe = false;
    String currentAuthUid = '';
    String remoteOrganizerUid = '';
    String remoteOwnerUid = '';

    try {
      currentAuthUid = _authUidOrRedirect() ?? '';
      if (currentAuthUid.isEmpty) return;

      await _requireOnline();

      league = await _repo
          .getLeagueById(widget.leagueId)
          .timeout(const Duration(seconds: 20));
      space = await _spaceRepo
          .getSpace(widget.leagueId)
          .timeout(const Duration(seconds: 10));

      try {
        final snap = await _firestore
            .collection('leagues')
            .doc(widget.leagueId)
            .get(const GetOptions(source: Source.server))
            .timeout(const Duration(seconds: 10));
        final data = snap.data();
        if (data != null) {
          remoteOrganizerUid =
              (data['organizerUid'] as String?)?.trim() ?? '';
          remoteOwnerUid = (data['ownerUid'] as String?)?.trim() ?? '';

          if (remoteOrganizerUid.isEmpty) {
            final legacyOrg =
                (data['organizerUserId'] as String?)?.trim() ?? '';
            if (legacyOrg.isNotEmpty && legacyOrg == currentAuthUid) {
              remoteOrganizerUid = currentAuthUid;
            }
          }
          if (remoteOwnerUid.isEmpty) {
            final legacyOwner = (data['ownerId'] as String?)?.trim() ?? '';
            if (legacyOwner.isNotEmpty && legacyOwner == currentAuthUid) {
              remoteOwnerUid = currentAuthUid;
            }
          }
        }
      } catch (_) {
        // best-effort
      }

      if (league != null) {
        final isOrganizer = _isRulesOwnerForLeague(
          league,
          authUid: currentAuthUid,
          remoteOrganizerUid: remoteOrganizerUid,
          remoteOwnerUid: remoteOwnerUid,
        );

        if (isOrganizer) {
          final teams = await _repo
              .getTeams(widget.leagueId)
              .timeout(const Duration(seconds: 20));
          final myTeamId = currentAuthUid;
          final alreadyParticipant =
              myTeamId.isNotEmpty && teams.any((t) => t.id == myTeamId);
          showAddMe = !alreadyParticipant;
        }
      }
    } catch (e) {
      _snack(
        UserFriendlyError.toMessage(e is Object ? e : Exception('unknown')),
      );
    }

    if (!mounted) return;
    setState(() {
      _league = league;
      _space = space;
      _currentAuthUid = currentAuthUid;
      _remoteOrganizerUid = remoteOrganizerUid;
      _remoteOwnerUid = remoteOwnerUid;
      _showAddMeAsParticipant = showAddMe;
      _isLeagueLoading = false;
    });
  }

  // ---------------------------------------------------------------------------
  // Purchase coupons / set discount
  // ---------------------------------------------------------------------------

  Future<void> _purchaseCouponsOrAdjustSubsidy() async {
    final league = _league;
    if (league == null) return;
    if (_processingUpgradePayment) return;

    if (!_canManageCoupons(league)) {
      _snack('Only the organizer can purchase add-ons.');
      return;
    }

    setState(() => _processingUpgradePayment = true);

    try {
      final authUid = _authUidOrRedirect();
      if (authUid == null) return;

      await _requireOnline();

      final result = await context.push<LeagueCreationPaymentResult?>(
        '/leagues/${league.id}/upgrade/payment',
        extra: <String, dynamic>{
          'leagueId': league.id,
          'leagueName': league.name,
          'addonsOnly': true,
          'existingCouponsEnabled': league.couponsEnabled,
          'existingCouponCount': league.couponCount,
          'existingCouponDiscountPercent': league.couponDiscountPercent,
        },
      );

      if (!mounted) return;

      if (result == null) {
        _snack('Payment cancelled.');
        return;
      }

      if (!result.success) {
        _snack(
          result.errorMessage?.trim().isNotEmpty == true
              ? result.errorMessage!
              : 'Payment failed',
        );
        return;
      }

      final addCoupons = result.buyCouponsForParticipants
          ? (result.couponCount < 0 ? 0 : result.couponCount)
          : 0;

      final nextCouponsEnabled =
          league.couponsEnabled || result.buyCouponsForParticipants;
      final nextDiscountPercent = result.buyCouponsForParticipants
          ? result.couponDiscountPercent
          : league.couponDiscountPercent;
      final nextCouponCount = league.couponCount + addCoupons;

      final now = DateTime.now().millisecondsSinceEpoch;

      final updated = league.copyWith(
        couponsEnabled: nextCouponsEnabled,
        couponDiscountPercent: nextDiscountPercent,
        couponCount: nextCouponCount,
        updatedAtMs: now,
      );

      await _repo.saveLeague(updated).timeout(const Duration(seconds: 25));

      try {
        final plan = await RemotePricingService.instance
            .getPlanForLocale(Localizations.maybeLocaleOf(context))
            .timeout(const Duration(seconds: 15));

        if (result.buyCouponsForParticipants) {
          await CouponConfigService()
              .createOrIncrementOnPurchase(
                leagueId: league.id,
                organizerUserId: authUid,
                qtyPurchased: addCoupons,
                discountPercent: nextDiscountPercent,
                plan: plan,
              )
              .timeout(const Duration(seconds: 20));
        }
      } catch (_) {
        if (mounted) {
          _snack(
            "We saved your purchase, but couldn't update coupons right now. Please try again.",
          );
        }
      }

      await _loadLeague();
      if (!mounted) return;
      _snack('Purchase successful.');
    } catch (e) {
      if (!mounted) return;
      _snack(
        UserFriendlyError.toMessage(e is Object ? e : Exception('unknown')),
      );
    } finally {
      if (mounted) setState(() => _processingUpgradePayment = false);
    }
  }

  // ---------------------------------------------------------------------------
  // Coupon Config sheet
  // ---------------------------------------------------------------------------

  void _showCouponsConfigSheet() {
    final league = _league;
    if (league == null) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        final cs = theme.colorScheme;
        final onSurface = cs.onSurface;

        final configStream = CouponConfigService().watchConfig(league.id);

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
                constraints: const BoxConstraints(maxWidth: 560),
                child: Glass(
                  borderRadius: 28,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: 12,
                      horizontal: 16,
                    ),
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
                          league.name,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: onSurface.withOpacity(0.70),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                        StreamBuilder<CouponConfig?>(
                          stream: configStream,
                          builder: (context, snap) {
                            if (snap.hasError) {
                              return Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 16),
                                child: Text(
                                  UserFriendlyError.toMessage(
                                    snap.error as Object,
                                  ),
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: cs.error,
                                    fontWeight: FontWeight.w700,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              );
                            }

                            if (snap.connectionState ==
                                ConnectionState.waiting) {
                              return Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 16),
                                child: Center(
                                  child: CircularProgressIndicator(
                                    color: cs.primary,
                                  ),
                                ),
                              );
                            }

                            final cfg = snap.data;
                            if (cfg == null) {
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Padding(
                                    padding:
                                        const EdgeInsets.symmetric(vertical: 8),
                                    child: Text(
                                      'No coupon configuration yet.',
                                      textAlign: TextAlign.center,
                                      style: theme.textTheme.bodySmall?.copyWith(
                                        color: onSurface.withOpacity(0.70),
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: OutlinedButton(
                                          onPressed: () =>
                                              Navigator.of(ctx).pop(),
                                          child: const Text('Close'),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: FilledButton.icon(
                                          onPressed: () {
                                            Navigator.of(ctx).pop();
                                            _purchaseCouponsOrAdjustSubsidy();
                                          },
                                          icon: const Icon(
                                            Icons.add_shopping_cart,
                                          ),
                                          label: const Text('Buy / enable'),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              );
                            }

                            final redeemed = cfg.qtyRedeemed;
                            final usersPay =
                                (100 - cfg.discountPercent).clamp(0, 100);

                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _kv('Currency', cfg.currency, theme, cs),
                                _kv(
                                  'Unit price',
                                  '${money(cfg.unitPrice)} ${cfg.currency}',
                                  theme,
                                  cs,
                                ),
                                _kv(
                                  'Effective unit',
                                  '${money(cfg.effectiveUnit)} ${cfg.currency}',
                                  theme,
                                  cs,
                                ),
                                _kv(
                                  'Threshold',
                                  cfg.threshold == null
                                      ? '\u2014'
                                      : '${money(cfg.threshold!)} ${cfg.currency}',
                                  theme,
                                  cs,
                                ),
                                _kv(
                                  'Threshold discount',
                                  '${money(cfg.thresholdDiscountPercent)}%',
                                  theme,
                                  cs,
                                ),
                                const Divider(),
                                _kv(
                                  'Discount',
                                  '${cfg.discountPercent}%',
                                  theme,
                                  cs,
                                ),
                                _kv(
                                  'Users pay (at redemption)',
                                  '$usersPay%',
                                  theme,
                                  cs,
                                ),
                                const Divider(),
                                _kv(
                                  'Purchased (total)',
                                  '${cfg.qtyTotal}',
                                  theme,
                                  cs,
                                ),
                                _kv(
                                  'Remaining',
                                  '${cfg.qtyRemaining}',
                                  theme,
                                  cs,
                                ),
                                _kv('Redeemed', '$redeemed', theme, cs),
                                const SizedBox(height: 16),
                                Row(
                                  children: [
                                    Expanded(
                                      child: OutlinedButton(
                                        onPressed: () =>
                                            Navigator.of(ctx).pop(),
                                        child: const Text('Close'),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: FilledButton.icon(
                                        onPressed: () {
                                          Navigator.of(ctx).pop();
                                          _purchaseCouponsOrAdjustSubsidy();
                                        },
                                        icon: const Icon(
                                          Icons.add_shopping_cart,
                                        ),
                                        label: const Text('Buy more / adjust'),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                FilledButton.icon(
                                  onPressed: () {
                                    Navigator.of(ctx).pop();
                                    _showCouponCodesSheet();
                                  },
                                  icon: const Icon(
                                    Icons.confirmation_number_outlined,
                                  ),
                                  label:
                                      const Text('Manage coupon codes'),
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

  // ---------------------------------------------------------------------------
  // Coupon Codes sheet
  // ---------------------------------------------------------------------------

  void _showCouponCodesSheet() {
    final league = _league;
    if (league == null) return;

    if (!_canManageCoupons(league)) {
      _snack('Only the organizer can manage coupon codes.');
      return;
    }

    final countCtrl = TextEditingController(text: '10');
    final customCtrl = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        final cs = theme.colorScheme;
        final onSurface = cs.onSurface;

        final cfgStream = CouponConfigService().watchConfig(league.id);

        final codesQuery = FirebaseFirestore.instance
            .collection('leagues')
            .doc(league.id)
            .collection('couponCodes')
            .orderBy('createdAtMs', descending: true)
            .limit(300);

        bool customMode = false;
        bool generating = false;
        String? errorText;

        return StatefulBuilder(
          builder: (ctx, setStateSheet) {
            Future<void> initConfigIfMissing() async {
              try {
                final authUid = _authUidOrRedirect();
                if (authUid == null) return;
                await _requireOnline();
                await CouponConfigService()
                    .ensureConfigInitializedFromLeague(league.id)
                    .timeout(const Duration(seconds: 15));
                if (!mounted) return;
                _snack('Coupon config initialized.');
              } catch (e) {
                setStateSheet(
                  () => errorText = UserFriendlyError.toMessage(
                    e is Object ? e : Exception('unknown'),
                  ),
                );
              }
            }

            Future<void> generate() async {
              if (generating) return;
              setStateSheet(() {
                generating = true;
                errorText = null;
              });

              try {
                final organizerAuthUid = _authUidOrRedirect();
                if (organizerAuthUid == null) return;

                await _requireOnline();

                final svc = CouponCodesService();

                if (customMode) {
                  final raw = customCtrl.text.trim();
                  if (raw.isEmpty) {
                    setStateSheet(() => errorText = 'Enter a custom code');
                    return;
                  }
                  final generated = await svc
                      .generateCodes(
                        leagueId: league.id,
                        organizerAuthUid: organizerAuthUid,
                        count: 1,
                        customCode: raw,
                      )
                      .timeout(const Duration(seconds: 20));
                  if (!mounted) return;
                  _snack(
                    generated.isEmpty
                        ? 'No code generated'
                        : 'Generated: ${generated.first}',
                  );
                  return;
                }

                final cnt = int.tryParse(countCtrl.text.trim()) ?? 0;
                if (cnt <= 0) {
                  setStateSheet(() => errorText = 'Enter a positive number');
                  return;
                }

                final requested = cnt.clamp(1, 500);
                final generated = await svc
                    .generateCodes(
                      leagueId: league.id,
                      organizerAuthUid: organizerAuthUid,
                      count: requested,
                    )
                    .timeout(const Duration(seconds: 25));
                if (!mounted) return;
                _snack('Generated ${generated.length} codes');
              } catch (e) {
                setStateSheet(
                  () => errorText = UserFriendlyError.toMessage(
                    e is Object ? e : Exception('unknown'),
                  ),
                );
              } finally {
                setStateSheet(() => generating = false);
              }
            }

            Widget modeChip({
              required String label,
              required bool selected,
              required VoidCallback onTap,
            }) {
              return ChoiceChip(
                label: Text(
                  label,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                selected: selected,
                onSelected: generating ? null : (_) => onTap(),
                selectedColor: cs.primary.withOpacity(0.18),
                backgroundColor: cs.onSurface.withOpacity(0.06),
                labelStyle: TextStyle(
                  color: selected
                      ? cs.primary
                      : cs.onSurface.withOpacity(0.72),
                  fontWeight:
                      selected ? FontWeight.w900 : FontWeight.w800,
                ),
              );
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
                        padding: const EdgeInsets.symmetric(
                          vertical: 12,
                          horizontal: 16,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Coupon Codes',
                              style: theme.textTheme.titleMedium?.copyWith(
                                color: onSurface,
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              league.name,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: onSurface.withOpacity(0.70),
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 10),
                            StreamBuilder<CouponConfig?>(
                              stream: cfgStream,
                              builder: (context, snap) {
                                final cfg = snap.data;

                                if (snap.hasError) {
                                  return Padding(
                                    padding:
                                        const EdgeInsets.only(bottom: 10),
                                    child: Text(
                                      UserFriendlyError.toMessage(
                                        snap.error as Object,
                                      ),
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                        color: cs.error,
                                        fontWeight: FontWeight.w800,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  );
                                }

                                if (snap.connectionState ==
                                    ConnectionState.waiting) {
                                  return Padding(
                                    padding:
                                        const EdgeInsets.only(bottom: 10),
                                    child: Row(
                                      children: [
                                        const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Text(
                                          'Loading coupon config...',
                                          style: theme.textTheme.bodySmall
                                              ?.copyWith(
                                            color:
                                                onSurface.withOpacity(0.70),
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }

                                if (cfg == null) {
                                  return Container(
                                    width: double.infinity,
                                    margin:
                                        const EdgeInsets.only(bottom: 10),
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      borderRadius:
                                          BorderRadius.circular(14),
                                      color:
                                          cs.onSurface.withOpacity(0.04),
                                      border: Border.all(
                                        color: cs.onSurface
                                            .withOpacity(0.10),
                                      ),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Coupon config missing',
                                          style: theme.textTheme.bodyMedium
                                              ?.copyWith(
                                            color: onSurface,
                                            fontWeight: FontWeight.w900,
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          'Initialize config to enable code generation (organizer only).',
                                          style: theme.textTheme.bodySmall
                                              ?.copyWith(
                                            color:
                                                onSurface.withOpacity(0.65),
                                            fontWeight: FontWeight.w600,
                                            height: 1.25,
                                          ),
                                        ),
                                        const SizedBox(height: 10),
                                        Align(
                                          alignment:
                                              Alignment.centerRight,
                                          child: FilledButton.icon(
                                            onPressed: generating
                                                ? null
                                                : initConfigIfMissing,
                                            icon: const Icon(
                                              Icons.build_circle_outlined,
                                            ),
                                            label:
                                                const Text('Initialize'),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }

                                final remaining = cfg.qtyRemaining;
                                final total = cfg.qtyTotal;
                                final soldOut = remaining <= 0;

                                return Container(
                                  width: double.infinity,
                                  margin:
                                      const EdgeInsets.only(bottom: 10),
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    borderRadius:
                                        BorderRadius.circular(14),
                                    color: cs.onSurface.withOpacity(0.04),
                                    border: Border.all(
                                      color:
                                          cs.onSurface.withOpacity(0.10),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        soldOut
                                            ? Icons.block
                                            : Icons
                                                .confirmation_number_outlined,
                                        color: soldOut
                                            ? cs.error
                                            : cs.primary,
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          soldOut
                                              ? 'No coupons remaining (sold out)'
                                              : 'Remaining: $remaining (Total purchased: $total)',
                                          style: theme.textTheme.bodySmall
                                              ?.copyWith(
                                            color: soldOut
                                                ? cs.error
                                                : onSurface
                                                    .withOpacity(0.80),
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                            Row(
                              children: [
                                modeChip(
                                  label: 'Random',
                                  selected: !customMode,
                                  onTap: () => setStateSheet(() {
                                    customMode = false;
                                    errorText = null;
                                  }),
                                ),
                                const SizedBox(width: 10),
                                modeChip(
                                  label: 'Custom',
                                  selected: customMode,
                                  onTap: () => setStateSheet(() {
                                    customMode = true;
                                    errorText = null;
                                  }),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            if (!customMode) ...[
                              Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      controller: countCtrl,
                                      keyboardType: TextInputType.number,
                                      decoration: const InputDecoration(
                                        labelText:
                                            'How many random codes?',
                                        prefixIcon: Icon(Icons.numbers),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  FilledButton.icon(
                                    onPressed:
                                        generating ? null : generate,
                                    icon: generating
                                        ? const SizedBox(
                                            width: 16,
                                            height: 16,
                                            child:
                                                CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: Colors.white,
                                            ),
                                          )
                                        : const Icon(Icons.add),
                                    label: const Text('Generate'),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Random codes are one-time use and reduce qtyRemaining by 1 per code.',
                                style:
                                    theme.textTheme.bodySmall?.copyWith(
                                  color: onSurface.withOpacity(0.60),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ] else ...[
                              Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      controller: customCtrl,
                                      decoration: const InputDecoration(
                                        labelText: 'Custom code (single)',
                                        prefixIcon: Icon(Icons.edit),
                                        hintText:
                                            'BARCA (creates: ESL_BARCA_<DISCOUNT>%)',
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  FilledButton.icon(
                                    onPressed:
                                        generating ? null : generate,
                                    icon: generating
                                        ? const SizedBox(
                                            width: 16,
                                            height: 16,
                                            child:
                                                CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: Colors.white,
                                            ),
                                          )
                                        : const Icon(Icons.check),
                                    label: const Text('Create'),
                                  ),
                                ],
                              ),
                            ],
                            if (errorText != null) ...[
                              const SizedBox(height: 8),
                              Text(
                                errorText!,
                                style:
                                    theme.textTheme.bodySmall?.copyWith(
                                  color: cs.error,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                            const SizedBox(height: 12),
                            Divider(color: onSurface.withOpacity(0.12)),
                            ConstrainedBox(
                              constraints:
                                  const BoxConstraints(maxHeight: 440),
                              child: StreamBuilder<
                                  QuerySnapshot<Map<String, dynamic>>>(
                                stream: codesQuery.snapshots(),
                                builder: (context, snap) {
                                  if (snap.hasError) {
                                    return Center(
                                      child: Text(
                                        UserFriendlyError.toMessage(
                                          snap.error as Object,
                                        ),
                                        style: theme.textTheme.bodyMedium
                                            ?.copyWith(
                                          color: cs.error,
                                          fontWeight: FontWeight.w700,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                    );
                                  }
                                  if (!snap.hasData) {
                                    return Center(
                                      child: CircularProgressIndicator(
                                        color: cs.primary,
                                      ),
                                    );
                                  }
                                  final docs = snap.data!.docs;
                                  if (docs.isEmpty) {
                                    return Center(
                                      child: Text(
                                        'No codes yet.',
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(
                                          color:
                                              onSurface.withOpacity(0.70),
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    );
                                  }
                                  return ListView.separated(
                                    itemCount: docs.length,
                                    separatorBuilder: (_, __) => Divider(
                                      color: onSurface.withOpacity(0.10),
                                    ),
                                    itemBuilder: (context, i) {
                                      final d = docs[i].data();
                                      final code = docs[i].id;
                                      final usedBy =
                                          (d['usedBy'] as String?) ?? '';
                                      final isUsed =
                                          usedBy.trim().isNotEmpty;
                                      return ListTile(
                                        dense: true,
                                        contentPadding: EdgeInsets.zero,
                                        leading: Icon(
                                          isUsed
                                              ? Icons.verified
                                              : Icons
                                                  .confirmation_number_outlined,
                                          color: isUsed
                                              ? const Color(0xFF22C55E)
                                              : cs.primary,
                                        ),
                                        title: Text(
                                          code,
                                          style: theme.textTheme.bodyMedium
                                              ?.copyWith(
                                            color: onSurface,
                                            fontWeight: FontWeight.w900,
                                          ),
                                        ),
                                        subtitle: Text(
                                          isUsed ? 'Used' : 'Unused',
                                          style: theme.textTheme.bodySmall
                                              ?.copyWith(
                                            color:
                                                onSurface.withOpacity(0.65),
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        trailing: IconButton(
                                          tooltip: 'Copy',
                                          icon: Icon(
                                            Icons.copy,
                                            color: onSurface
                                                .withOpacity(0.72),
                                          ),
                                          onPressed: () async {
                                            await Clipboard.setData(
                                              ClipboardData(text: code),
                                            );
                                            if (!context.mounted) return;
                                            _snack('Copied: $code');
                                          },
                                        ),
                                      );
                                    },
                                  );
                                },
                              ),
                            ),
                            const SizedBox(height: 10),
                            FilledButton(
                              onPressed: () => Navigator.of(ctx).pop(),
                              child: const Text('Close'),
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
      },
    ).whenComplete(() {
      countCtrl.dispose();
      customCtrl.dispose();
    });
  }

  Widget _kv(String k, String v, ThemeData theme, ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
            width: 160,
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

  // ---------------------------------------------------------------------------
  // Add me as participant
  // ---------------------------------------------------------------------------

  Future<void> _addMeAsParticipant() async {
    final l10n = context.l10n;
    final league = _league;
    if (league == null) {
      _snack(l10n.tr('league_admin_league_info_not_loaded_yet'));
      return;
    }
    if (_addingMeAsParticipant) return;

    setState(() => _addingMeAsParticipant = true);

    try {
      final authUid = _authUidOrRedirect();
      if (authUid == null) return;

      await _requireOnline();

      final isOwnerByRules = _isRulesOwnerForLeague(
        league,
        authUid: authUid,
        remoteOrganizerUid: _remoteOrganizerUid,
        remoteOwnerUid: _remoteOwnerUid,
      );

      if (!isOwnerByRules) {
        throw UserFriendlyException(
          l10n.tr('league_admin_only_organizer_action'),
        );
      }

      if (league.format == LeagueFormat.uclGroup &&
          !(league.maxTeams == 16 || league.maxTeams == 32)) {
        throw UserFriendlyException(
          l10n.tr('league_admin_ucl_group_maxteams_error'),
        );
      }
      if (league.format == LeagueFormat.uclSwiss &&
          !(league.maxTeams == 18 || league.maxTeams == 36)) {
        throw UserFriendlyException(
          l10n.tr('league_admin_swiss_maxteams_error'),
        );
      }

      final existingTeams =
          await _repo.getTeams(league.id).timeout(const Duration(seconds: 20));
      final alreadyHasTeam = existingTeams.any((t) => t.id == authUid);
      if (alreadyHasTeam) {
        _snack(l10n.tr('league_admin_already_added_participant_team_exists'));
        return;
      }

      if (existingTeams.length >= league.maxTeams) {
        final prefix = l10n.tr('league_admin_league_full_prefix');
        final suffix = l10n.tr('league_admin_league_full_suffix');
        throw UserFriendlyException('$prefix${league.maxTeams}$suffix');
      }

      final profile = await UserProfileRepository()
          .fetchByUserId(authUid)
          .timeout(const Duration(seconds: 12));
      final teamName = profile?.teamName.trim() ?? '';
      if (teamName.isEmpty) {
        throw UserFriendlyException(
          l10n.tr('league_admin_profile_team_name_missing'),
        );
      }

      String? groupId;
      if (league.format == LeagueFormat.uclGroup) {
        final allowedGroups = _allowedGroupsForUclGroup(league);
        final picked = _pickGroupWithSpace(
          teams: existingTeams,
          allowedGroups: allowedGroups,
        );
        if (picked == null) {
          throw UserFriendlyException(
            l10n.tr('league_admin_all_groups_full'),
          );
        }
        groupId = picked;
      } else {
        groupId = null;
      }

      final now = DateTime.now().millisecondsSinceEpoch;

      final team = Team(
        id: authUid,
        leagueId: league.id,
        name: teamName,
        groupId: groupId,
        updatedAtMs: now,
        version: 1,
      );

      await _repo
          .saveTeams(league.id, <Team>[...existingTeams, team])
          .timeout(const Duration(seconds: 25));

      await _repo
          .assignTeamToUserInLeague(
            leagueId: league.id,
            userId: authUid,
            teamId: authUid,
          )
          .timeout(const Duration(seconds: 20));

      if (!mounted) return;
      await _loadLeague();

      final String msg;
      if (groupId == null) {
        msg = l10n.tr('league_admin_added_participant');
      } else {
        final groupPrefix =
            l10n.tr('league_admin_added_participant_in_group_prefix');
        final groupName = _groupDisplayName(l10n, groupId);
        msg = '$groupPrefix $groupName.';
      }
      _snack(msg);
    } catch (e) {
      if (!mounted) return;
      final failPrefix =
          l10n.tr('league_admin_failed_add_participant_prefix');
      _snack(
        '$failPrefix ${UserFriendlyError.toMessage(e is Object ? e : Exception('unknown'))}',
      );
    } finally {
      if (mounted) setState(() => _addingMeAsParticipant = false);
    }
  }

  // ---------------------------------------------------------------------------
  // Export roster CSV
  // ---------------------------------------------------------------------------

  Future<void> _exportRosterCsv() async {
    final l10n = context.l10n;
    final league = _league;
    if (league == null) {
      _snack(l10n.tr('league_admin_league_info_not_loaded_yet'));
      return;
    }
    if (_exportingRoster) return;

    setState(() => _exportingRoster = true);
    try {
      final authUid = _authUidOrRedirect();
      if (authUid == null) return;
      await _requireOnline();
      await RosterCsvExporter.shareRosterCsv(repo: _repo, league: league);
    } catch (e) {
      if (!mounted) return;
      final prefix = l10n.tr('league_admin_export_failed_prefix');
      _snack(
        '$prefix ${UserFriendlyError.toMessage(e is Object ? e : Exception('unknown'))}',
      );
    } finally {
      if (mounted) setState(() => _exportingRoster = false);
    }
  }

  // ---------------------------------------------------------------------------
  // Space: start / open / end
  // ---------------------------------------------------------------------------

  Future<void> _startSpace() async {
    final l10n = context.l10n;
    final league = _league;

    if (league == null) {
      _snack(l10n.tr('league_admin_league_info_not_loaded_yet'));
      return;
    }

    try {
      final authUid = _authUidOrRedirect();
      if (authUid == null) return;
      await _requireOnline();

      final isOwnerByRules = _isRulesOwnerForLeague(
        league,
        authUid: authUid,
        remoteOrganizerUid: _remoteOrganizerUid,
        remoteOwnerUid: _remoteOwnerUid,
      );

      if (!isOwnerByRules) {
        throw UserFriendlyException(
          l10n.tr('league_admin_only_organizer_start_space'),
        );
      }

      final leagueName = league.name;
      final suffix = l10n.tr('league_details_space_title_suffix');
      final spaceTitle = '$leagueName $suffix';

      final space = await _spaceRepo
          .startSpace(
            leagueId: league.id,
            hostUserId: authUid,
            title: spaceTitle,
          )
          .timeout(const Duration(seconds: 20));

      if (!mounted) return;
      setState(() => _space = space);
      _snack(l10n.tr('league_details_space_started'));
    } catch (e) {
      if (!mounted) return;
      _snack(
        UserFriendlyError.toMessage(e is Object ? e : Exception('unknown')),
      );
    }
  }

  void _onOpenSpace() {
    final l10n = context.l10n;
    if (_league == null) {
      _snack(l10n.tr('league_admin_league_info_not_loaded_yet'));
      return;
    }
    context.push('/leagues/${_league!.id}/space');
  }

  Future<void> _endSpace() async {
    final l10n = context.l10n;
    final league = _league;
    if (league == null) return;

    try {
      final authUid = _authUidOrRedirect();
      if (authUid == null) return;
      await _requireOnline();

      final isOwnerByRules = _isRulesOwnerForLeague(
        league,
        authUid: authUid,
        remoteOrganizerUid: _remoteOrganizerUid,
        remoteOwnerUid: _remoteOwnerUid,
      );

      if (!isOwnerByRules) {
        throw UserFriendlyException(
          l10n.tr('league_admin_only_organizer_end_space'),
        );
      }

      final updated =
          await _spaceRepo.endSpace(league.id).timeout(const Duration(seconds: 20));

      if (!mounted) return;
      setState(() => _space = updated);
      _snack(l10n.tr('league_details_space_ended'));
    } catch (e) {
      if (!mounted) return;
      _snack(
        UserFriendlyError.toMessage(e is Object ? e : Exception('unknown')),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;

    return GlassScaffold(
      appBar: AppBar(
        title: Text(l10n.tr('league_admin_appbar_title')),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: l10n.tr('common_refresh'),
            onPressed: _isLeagueLoading ? null : _loadLeague,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                children: [
                  _buildInfoCard(),
                  const SizedBox(height: 20),
                  Expanded(
                    child: _isLeagueLoading
                        ? Center(
                            child: CircularProgressIndicator(
                              color: cs.primary,
                            ),
                          )
                        : _buildSettingsList(context),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInfoCard() {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return ValueListenableBuilder<bool>(
      valueListenable: ConnectivityService.instance.isConnected,
      builder: (context, online, _) {
        final title = online ? 'Online' : 'Offline';
        final subtitle = online
            ? 'All changes are saved to the server instantly.'
            : 'You appear to be offline. Some actions may not work.';
        final statusIcon = online ? Icons.wifi : Icons.wifi_off;
        final statusColor =
            online ? const Color(0xFF22C55E) : const Color(0xFFF59E0B);

        return Glass(
          borderRadius: 24,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(statusIcon, color: statusColor, size: 40),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: cs.onSurface,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        subtitle,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.onSurface.withOpacity(0.70),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: l10n.tr('common_refresh'),
                  onPressed: _loadLeague,
                  icon: Icon(
                    Icons.refresh,
                    color: cs.onSurface.withOpacity(0.72),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSettingsList(BuildContext context) {
    final l10n = context.l10n;
    final league = _league;

    return ListView(
      children: [
        if (league != null && _canManageCoupons(league))
          _buildSettingsTile(
            context,
            Icons.payments_outlined,
            _processingUpgradePayment
                ? 'Processing payment...'
                : 'Buy coupons / set discount',
            _couponSubtitleFromLeague(league),
            onTap: _processingUpgradePayment
                ? null
                : _purchaseCouponsOrAdjustSubsidy,
          ),
        if (league != null)
          _buildSettingsTile(
            context,
            Icons.confirmation_number_outlined,
            'Coupons',
            league.couponsEnabled
                ? _couponSubtitleFromLeague(league)
                : 'Not enabled',
            onTap: _showCouponsConfigSheet,
          ),
        if (league != null && _canManageCoupons(league))
          _buildSettingsTile(
            context,
            Icons.qr_code,
            'Coupon Codes',
            'Generate and manage one-time codes',
            onTap: _showCouponCodesSheet,
          ),
        _buildSettingsTile(
          context,
          Icons.group_add,
          l10n.tr('league_admin_manage_teams_title'),
          l10n.tr('league_admin_manage_teams_subtitle'),
          onTap: _showParticipantsOptionsSheet,
        ),
        if (_showAddMeAsParticipant)
          _buildSettingsTile(
            context,
            Icons.person_add_alt_1,
            _addingMeAsParticipant
                ? l10n.tr('league_admin_adding_you')
                : l10n.tr('league_admin_add_me_participant'),
            l10n.tr('league_admin_add_me_participant_subtitle'),
            onTap: _addingMeAsParticipant ? null : _addMeAsParticipant,
          ),
        _buildSettingsTile(
          context,
          Icons.file_download_outlined,
          _exportingRoster
              ? l10n.tr('league_admin_exporting_roster')
              : l10n.tr('league_admin_export_roster'),
          l10n.tr('league_admin_export_roster_subtitle'),
          onTap: _exportingRoster ? null : _exportRosterCsv,
        ),
        _buildSettingsTile(
          context,
          Icons.people_outline,
          l10n.tr('league_admin_view_participants'),
          l10n.tr('league_admin_view_participants_subtitle'),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    LeagueParticipantsScreen(leagueId: widget.leagueId),
              ),
            );
          },
        ),
        _buildSettingsTile(
          context,
          Icons.mic,
          l10n.tr('league_admin_live_voice_settings'),
          l10n.tr('league_admin_live_voice_settings_subtitle'),
          onTap: _showLiveSettingsSheet,
        ),
        _buildSettingsTile(
          context,
          Icons.spatial_audio_off,
          _space?.isLive == true
              ? l10n.tr('league_admin_league_space_live')
              : l10n.tr('league_admin_league_space_voice_room'),
          _space?.isLive == true
              ? l10n.tr('league_admin_league_space_live_subtitle')
              : l10n.tr('league_admin_league_space_voice_room_subtitle'),
          onTap: _showLeagueSpaceAdminSheet,
        ),
        _buildSettingsTile(
          context,
          Icons.notifications_active,
          l10n.tr('league_admin_send_announcement'),
          l10n.tr('league_admin_send_announcement_subtitle'),
          onTap: _showSendAnnouncementSheet,
        ),
        _buildSettingsTile(
          context,
          Icons.rule,
          l10n.tr('league_admin_league_rules'),
          l10n.tr('league_admin_league_rules_subtitle'),
          onTap: _showRulesSheet,
        ),
        _buildSettingsTile(
          context,
          Icons.delete_forever,
          l10n.tr('league_admin_delete_league'),
          l10n.tr('league_admin_delete_league_subtitle'),
          isDestructive: true,
          onTap: _confirmDeleteLeague,
        ),
      ],
    );
  }

  Widget _buildSettingsTile(
    BuildContext context,
    IconData icon,
    String title,
    String subtitle, {
    bool isDestructive = false,
    VoidCallback? onTap,
  }) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isRtl = Directionality.of(context) == TextDirection.rtl;
    final chevronIcon = isRtl ? Icons.chevron_left : Icons.chevron_right;
    final leadingColor = isDestructive ? cs.error : cs.primary;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Glass(
        borderRadius: 20,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(icon, color: leadingColor),
            title: Text(
              title,
              style: theme.textTheme.titleSmall?.copyWith(
                color: cs.onSurface,
                fontWeight: FontWeight.w900,
              ),
            ),
            subtitle: Text(
              subtitle,
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurface.withOpacity(0.65),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            trailing:
                Icon(chevronIcon, color: cs.onSurface.withOpacity(0.30)),
            onTap: onTap,
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Live settings sheet
  // ---------------------------------------------------------------------------

  void _showLiveSettingsSheet() {
    final l10n = context.l10n;
    final prefs = ref.read(prefsServiceProvider);

    bool chatEnabled = prefs.liveViewerChatEnabled();
    bool voiceEnabled = prefs.liveViewerVoiceEnabled();
    bool reactionsEnabled = prefs.liveViewerReactionsEnabled();

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            final theme = Theme.of(ctx);
            final cs = theme.colorScheme;
            final onSurface = cs.onSurface;

            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: Glass(
                      borderRadius: 28,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: 8,
                          horizontal: 12,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 12),
                              child: Text(
                                l10n.tr('league_admin_live_voice_settings'),
                                style: theme.textTheme.titleMedium?.copyWith(
                                  color: onSurface,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                            Divider(color: onSurface.withOpacity(0.12)),
                            SwitchListTile.adaptive(
                              value: chatEnabled,
                              onChanged: (v) =>
                                  setModalState(() => chatEnabled = v),
                              activeColor: cs.primary,
                              title: Text(
                                l10n.tr('league_admin_viewer_text_chat'),
                                style: TextStyle(
                                  color: onSurface,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              subtitle: Text(
                                l10n.tr(
                                  'league_admin_viewer_text_chat_subtitle',
                                ),
                                style: TextStyle(
                                  color: onSurface.withOpacity(0.65),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            SwitchListTile.adaptive(
                              value: voiceEnabled,
                              onChanged: (v) =>
                                  setModalState(() => voiceEnabled = v),
                              activeColor: cs.primary,
                              title: Text(
                                l10n.tr('league_admin_viewer_audio'),
                                style: TextStyle(
                                  color: onSurface,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              subtitle: Text(
                                l10n.tr(
                                  'league_admin_viewer_audio_subtitle',
                                ),
                                style: TextStyle(
                                  color: onSurface.withOpacity(0.65),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            SwitchListTile.adaptive(
                              value: reactionsEnabled,
                              onChanged: (v) => setModalState(
                                () => reactionsEnabled = v,
                              ),
                              activeColor: cs.primary,
                              title: Text(
                                l10n.tr('league_admin_viewer_reactions'),
                                style: TextStyle(
                                  color: onSurface,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              subtitle: Text(
                                l10n.tr(
                                  'league_admin_viewer_reactions_subtitle',
                                ),
                                style: TextStyle(
                                  color: onSurface.withOpacity(0.65),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            Align(
                              alignment: Alignment.centerRight,
                              child: Padding(
                                padding: const EdgeInsets.only(
                                  top: 8,
                                  right: 4,
                                  bottom: 8,
                                ),
                                child: FilledButton(
                                  onPressed: () async {
                                    await prefs.setLiveViewerChatEnabled(
                                      chatEnabled,
                                    );
                                    await prefs.setLiveViewerVoiceEnabled(
                                      voiceEnabled,
                                    );
                                    await prefs
                                        .setLiveViewerReactionsEnabled(
                                      reactionsEnabled,
                                    );
                                    if (!mounted) return;
                                    Navigator.of(ctx).pop();
                                    _snack(
                                      l10n.tr(
                                        'league_admin_live_viewer_settings_updated',
                                      ),
                                    );
                                  },
                                  child: Text(l10n.tr('common_save')),
                                ),
                              ),
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
      },
    );
  }

  // ---------------------------------------------------------------------------
  // League space admin sheet
  // ---------------------------------------------------------------------------

  void _showLeagueSpaceAdminSheet() {
    final l10n = context.l10n;
    final leagueName =
        _league?.name ?? l10n.tr('common_league_placeholder');
    final spaceLive = _space?.isLive == true;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        final cs = theme.colorScheme;
        final onSurface = cs.onSurface;

        final runningPrefix =
            l10n.tr('league_admin_league_space_running_prefix');
        final startPrefix =
            l10n.tr('league_admin_league_space_start_description_prefix');
        final startSuffix =
            l10n.tr('league_admin_league_space_start_description_suffix');

        final descText = spaceLive
            ? '$runningPrefix $leagueName.'
            : '$startPrefix $leagueName$startSuffix';

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Glass(
                  borderRadius: 28,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: 12,
                      horizontal: 16,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          l10n.tr(
                            'league_admin_league_space_sheet_title',
                          ),
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: onSurface,
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          descText,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: onSurface.withOpacity(0.70),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        if (!spaceLive) ...[
                          Row(
                            children: [
                              Expanded(
                                child: TextButton(
                                  onPressed: () =>
                                      Navigator.of(ctx).pop(),
                                  child: Text(
                                    l10n.tr('profile_close_tooltip'),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: FilledButton.icon(
                                  onPressed: () {
                                    Navigator.of(ctx).pop();
                                    _startSpace();
                                  },
                                  icon: const Icon(Icons.mic),
                                  label: Text(
                                    l10n.tr('league_admin_start_space'),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ] else ...[
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () {
                                    Navigator.of(ctx).pop();
                                    _onOpenSpace();
                                  },
                                  icon: const Icon(Icons.headset),
                                  label: Text(
                                    l10n.tr('league_admin_open_space'),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: FilledButton.icon(
                                  style: FilledButton.styleFrom(
                                    backgroundColor: cs.error,
                                  ),
                                  onPressed: () {
                                    Navigator.of(ctx).pop();
                                    _endSpace();
                                  },
                                  icon: const Icon(
                                    Icons.stop_circle_outlined,
                                  ),
                                  label: Text(
                                    l10n.tr('league_admin_end_space'),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
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

  // ---------------------------------------------------------------------------
  // Send announcement sheet
  // ---------------------------------------------------------------------------

  void _showSendAnnouncementSheet() {
    final l10n = context.l10n;

    final league = _league;
    if (league == null) {
      _snack(l10n.tr('league_admin_league_info_not_loaded_yet'));
      return;
    }

    final authUid = _authUidOrRedirect();
    if (authUid == null) return;

    final isOwnerByRules = _isRulesOwnerForLeague(
      league,
      authUid: authUid,
      remoteOrganizerUid: _remoteOrganizerUid,
      remoteOwnerUid: _remoteOwnerUid,
    );
    if (!isOwnerByRules) {
      _snack('Only the organizer can send announcements.');
      return;
    }

    final titleController = TextEditingController();
    final messageController = TextEditingController();

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        final cs = theme.colorScheme;
        final onSurface = cs.onSurface;

        return SafeArea(
          child: Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom,
            ).add(const EdgeInsets.all(16)),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Glass(
                  borderRadius: 28,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: 12,
                      horizontal: 16,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          l10n.tr(
                            'league_admin_send_announcement_sheet_title',
                          ),
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: onSurface,
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          l10n.tr(
                            'league_admin_send_announcement_sheet_subtitle',
                          ),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: onSurface.withOpacity(0.70),
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: titleController,
                          decoration: InputDecoration(
                            labelText: l10n.tr(
                              'league_admin_announcement_title_optional',
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: messageController,
                          maxLines: 3,
                          decoration: InputDecoration(
                            labelText: l10n.tr(
                              'league_admin_announcement_message_label',
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: TextButton(
                                onPressed: () =>
                                    Navigator.of(ctx).pop(),
                                child: Text(l10n.tr('common_cancel')),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: FilledButton(
                                onPressed: () async {
                                  final rawTitle =
                                      titleController.text.trim();
                                  final msg =
                                      messageController.text.trim();
                                  if (msg.isEmpty) return;

                                  final title = rawTitle.isEmpty
                                      ? l10n.tr(
                                          'league_admin_announcement_default_title',
                                        )
                                      : rawTitle;

                                  final now = DateTime.now()
                                      .millisecondsSinceEpoch;

                                  final ann = LeagueAnnouncement(
                                    id: _uuid.v4(),
                                    leagueId: widget.leagueId,
                                    title: title,
                                    message: msg,
                                    createdAtMs: now,
                                  );

                                  try {
                                    await _requireOnline();

                                    await _firestore
                                        .collection('leagues')
                                        .doc(widget.leagueId)
                                        .collection('announcements')
                                        .doc(ann.id)
                                        .set(
                                          ann.toMap(),
                                          SetOptions(merge: true),
                                        )
                                        .timeout(
                                          const Duration(seconds: 15),
                                        );

                                    try {
                                      await NotificationService()
                                          .showLeagueAnnouncementNotification(
                                        leagueName: league.name,
                                        title: title,
                                        message: msg,
                                      );
                                    } catch (_) {
                                      // Non-fatal.
                                    }

                                    if (!ctx.mounted) return;
                                    Navigator.of(ctx).pop();
                                    _snack(
                                      l10n.tr(
                                        'league_admin_announcement_sent',
                                      ),
                                    );
                                  } catch (e) {
                                    if (!ctx.mounted) return;
                                    _snack(
                                      UserFriendlyError.toMessage(
                                        e is Object
                                            ? e
                                            : Exception('unknown'),
                                      ),
                                    );
                                  }
                                },
                                child: Text(l10n.tr('league_admin_send')),
                              ),
                            ),
                          ],
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
    ).whenComplete(() {
      titleController.dispose();
      messageController.dispose();
    });
  }

  // ---------------------------------------------------------------------------
  // Participants options sheet
  // ---------------------------------------------------------------------------

  void _showParticipantsOptionsSheet() {
    final l10n = context.l10n;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        final cs = theme.colorScheme;
        final onSurface = cs.onSurface;

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 500),
                child: Glass(
                  borderRadius: 28,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: 8,
                      horizontal: 8,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Padding(
                          padding:
                              const EdgeInsets.symmetric(vertical: 12),
                          child: Text(
                            l10n.tr('league_admin_manage_teams_title'),
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: onSurface,
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        Divider(color: onSurface.withOpacity(0.12)),
                        ListTile(
                          leading: CircleAvatar(
                            backgroundColor: cs.primary,
                            child: Icon(
                              Icons.group,
                              color: cs.onPrimary,
                            ),
                          ),
                          title: Text(
                            l10n.tr(
                              'league_admin_teams_add_edit_title',
                            ),
                            style: TextStyle(
                              color: onSurface,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          subtitle: Text(
                            l10n.tr(
                              'league_admin_teams_add_edit_subtitle',
                            ),
                            style: TextStyle(
                              color: onSurface.withOpacity(0.55),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          onTap: () {
                            Navigator.of(ctx).pop();
                            _openAddTeams();
                          },
                        ),
                        const SizedBox(height: 8),
                        ListTile(
                          leading: CircleAvatar(
                            backgroundColor:
                                onSurface.withOpacity(0.08),
                            child:
                                Icon(Icons.people, color: onSurface),
                          ),
                          title: Text(
                            l10n.tr(
                              'league_admin_joined_participants_title',
                            ),
                            style: TextStyle(
                              color: onSurface,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          subtitle: Text(
                            l10n.tr(
                              'league_admin_joined_participants_subtitle',
                            ),
                            style: TextStyle(
                              color: onSurface.withOpacity(0.55),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          onTap: () {
                            Navigator.of(ctx).pop();
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => LeagueParticipantsScreen(
                                  leagueId: widget.leagueId,
                                ),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 12),
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

  void _openAddTeams() {
    final l10n = context.l10n;

    if (_league == null) {
      _snack(
        l10n.tr('league_admin_league_info_not_loaded_yet_try_again'),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AddTeamsScreen(
          leagueId: widget.leagueId,
          format: _league!.format,
        ),
      ),
    );
  }

  void _showRulesSheet() {
    final l10n = context.l10n;
    _snack(l10n.tr('league_admin_rules_editor_unchanged'));
  }

  void _confirmDeleteLeague() {
    final l10n = context.l10n;

    showDialog(
      context: context,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        final onSurface = cs.onSurface;

        return AlertDialog(
          backgroundColor: cs.surface,
          title: Text(
            l10n.tr('league_admin_delete_league_confirm_title'),
            style: TextStyle(
              color: onSurface,
              fontWeight: FontWeight.w900,
            ),
          ),
          content: Text(
            l10n.tr('league_admin_delete_league_confirm_message'),
            style: TextStyle(
              color: onSurface.withOpacity(0.72),
              fontWeight: FontWeight.w600,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(l10n.tr('common_cancel')),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: cs.error),
              onPressed: () async {
                try {
                  final uid = _authUidOrRedirect();
                  if (uid == null) return;

                  await _requireOnline();

                  await _repo
                      .deleteLeagueCompletely(widget.leagueId)
                      .timeout(const Duration(seconds: 30));
                  if (!mounted) return;
                  Navigator.of(ctx).pop();
                  GoRouter.of(context).go('/leagues');
                  _snack(l10n.tr('league_admin_league_deleted'));
                } catch (e) {
                  if (!mounted) return;
                  Navigator.of(ctx).pop();
                  _snack(
                    UserFriendlyError.toMessage(
                      e is Object ? e : Exception('unknown'),
                    ),
                  );
                }
              },
              child: Text(l10n.tr('league_admin_delete')),
            ),
          ],
        );
      },
    );
  }
}
