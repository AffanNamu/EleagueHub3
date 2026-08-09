//lib/features/leagues/presentation/league_list_screen
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:eleaguehub3/core/errors/user_friendly_error.dart';
import 'package:eleaguehub3/core/locale/app_localizations.dart';
import 'package:eleaguehub3/core/theme/app_theme.dart';
import 'package:eleaguehub3/core/services/plan_status_service.dart';
import 'package:eleaguehub3/features/leagues/logic/coupon_codes_service.dart';
import 'package:eleaguehub3/features/leagues/logic/league_access_service.dart';
import 'package:eleaguehub3/features/leagues/logic/league_charges_payment_service.dart';
import 'package:eleaguehub3/features/leagues/logic/league_charges_store.dart';
import 'package:eleaguehub3/features/leagues/models/enums.dart';
import 'package:eleaguehub3/features/leagues/models/football_category.dart';
import 'package:eleaguehub3/features/leagues/models/league.dart';
import 'package:eleaguehub3/features/leagues/models/league_announcement.dart';
import 'package:eleaguehub3/features/leagues/models/league_format.dart';
import 'package:eleaguehub3/features/leagues/models/league_settings.dart';
import 'package:eleaguehub3/features/leagues/models/membership.dart';
import 'package:eleaguehub3/features/master_leagues/logic/master_leagues_providers.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/config/payment_platform_config.dart';
import '../../../core/persistence/prefs_service.dart';
import '../../../core/services/payments/google_play_billing_catalog.dart';
import '../../../core/services/payments/google_play_billing_service.dart';
import '../../../core/services/payments/payments_service.dart';
import '../../../core/services/payments/payment_models.dart';
import '../../../core/services/rewarded_ad_manager.dart';
import '../../../core/widgets/glass.dart';
import '../../../core/widgets/glass_scaffold.dart';
import '../../../widgets/league_flip_card.dart';
import '../data/leagues_repository_local.dart';
import '../logic/league_creation_payment_service.dart';
import '../logic/league_premium_upgrade_helper.dart';

enum _LeagueViewTab { leagues, master }

class LeaguesListScreen extends ConsumerStatefulWidget {
  const LeaguesListScreen({
    super.key,
    this.showAppBar = true,
  });

  final bool showAppBar;

  @override
  ConsumerState<LeaguesListScreen> createState() =>
      _LeaguesListScreenState();
}

class _LeaguesListScreenState
    extends ConsumerState<LeaguesListScreen>
    with AutomaticKeepAliveClientMixin {
  static const Color _premiumAmber = Color(0xFFF59E0B);
  static const int _freeLeagueListLimit = 3;

  late final LocalLeaguesRepository _repo;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  late final TextEditingController _searchController;

  List<League> _leagues = [];
  Map<String, int> _participantCounts = {};
  Map<String, LeagueAnnouncement?> _latestAnnouncements = {};
  Map<String, bool> _viewerChargesPaid = {};
  Map<String, bool> _viewerIsParticipantByLeagueId = {};

  String _effectiveUserId = '';
  bool _isLoading = true;
  bool _loadingAnnouncements = false;

  bool _checkingPlan = true;
  bool _hasLeagueAccess = false;
  bool _isPremiumUser = false;
  int _createdLeagueCount = 0;

  String? _payingLeagueId;
  String? _removingLeagueId;
  String _searchQuery = '';
  _LeagueViewTab _selectedTab = _LeagueViewTab.leagues;

  FootballCategory? _categoryFilter;
  bool _rewardGateInProgress = false;
  bool _planUpgradeInProgress = false;

  @override
  bool get wantKeepAlive => true;

  String _authUidOrEmpty() =>
      FirebaseAuth.instance.currentUser?.uid.trim() ?? '';

  bool _looksLikeFirebaseUid(String s) => s.trim().length > 20;

  bool _isOwnerForViewer(League league, String viewerUid) {
    final v = viewerUid.trim();
    if (v.isEmpty) return false;

    final orgUid = league.organizerUid.trim();
    if (orgUid.isNotEmpty) return orgUid == v;

    final legacy = league.organizerUserId.trim();
    return legacy.isNotEmpty &&
        legacy == v &&
        _looksLikeFirebaseUid(legacy);
  }

  bool get _freeLimitReached =>
      _hasLeagueAccess &&
      !_isPremiumUser &&
      _createdLeagueCount >= _freeLeagueListLimit;

  String _freeLimitMessage([String action = 'create more']) {
    return 'Basic users can create up to $_freeLeagueListLimit '
        'leagues/competitions total. This total is shared across normal '
        'leagues and competitions inside Organizer or Master League '
        'workspace. Upgrade to a paid plan to $action.';
  }

  @override
  void initState() {
    super.initState();
    _repo = LocalLeaguesRepository(ref.read(prefsServiceProvider));
    _searchController = TextEditingController();
    _searchController.addListener(_handleSearchChanged);
    _loadLeagues(showSpinner: true);
  }

  @override
  void dispose() {
    _searchController.removeListener(_handleSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _handleSearchChanged() {
    final next = _searchController.text;
    if (next == _searchQuery) return;
    if (!mounted) return;
    setState(() => _searchQuery = next);
  }

  // ── FIX: Strictly use PlanStatusService ──────────────────────────────────
  Future<bool> _detectPremiumUser(String uid) async {
    final trimmed = uid.trim();
    if (trimmed.isEmpty) return false;

    try {
      return await PlanStatusService.instance.isPaidPlanActive(trimmed, forceRefreshToken: true);
    } catch (_) {
      return false;
    }
  }

  Future<bool> _detectLeagueAccessFromPlan(String uid) async {
    final trimmed = uid.trim();
    return trimmed.isNotEmpty;
  }

  Future<int> _countCreatedLeaguesAcrossAllFlows(
      String uid) async {
    final trimmed = uid.trim();
    if (trimmed.isEmpty) return 0;

    final ids = <String>{};

    try {
      final snap = await _firestore
          .collection('leagues')
          .where('organizerUid', isEqualTo: trimmed)
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 20));

      ids.addAll(snap.docs.map((d) => d.id));
    } catch (_) {}

    if (_looksLikeFirebaseUid(trimmed)) {
      try {
        final snap = await _firestore
            .collection('leagues')
            .where('organizerUserId', isEqualTo: trimmed)
            .get(const GetOptions(source: Source.server))
            .timeout(const Duration(seconds: 20));

        ids.addAll(snap.docs.map((d) => d.id));
      } catch (_) {}
    }

    return ids.length;
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _openInlinePlanChooser() async {
    if (_planUpgradeInProgress) return;

    if (PaymentPlatformConfig
        .routeAndroidPaymentsToGooglePlayBilling) {
      await _openGooglePlayPlanUpgrade();
      return;
    }

    await _openFlutterwavePlanUpgrade();
  }

  Future<void> _openGooglePlayPlanUpgrade() async {
    if (_planUpgradeInProgress) return;

    setState(() => _planUpgradeInProgress = true);

    try {
      final uid = _authUidOrEmpty();
      if (uid.isEmpty) {
        _snack('Please sign in to continue.');
        return;
      }

      final success =
          await LeaguePremiumUpgradeHelper.openUpgradeFlow(
        context,
        leagueName: 'Organizer Plan',
      );

      if (!mounted) return;

      if (success) {
        _snack('Plan purchase completed. Refreshing access...');
        await _refreshLeagues();
        return;
      }

      _snack('Plan upgrade cancelled.');
    } catch (e) {
      if (!mounted) return;
      _snack(UserFriendlyError.toMessage(
          e is Object ? e : Exception('unknown')));
    } finally {
      if (mounted) {
        setState(() => _planUpgradeInProgress = false);
      }
    }
  }

  Future<void> _openFlutterwavePlanUpgrade() async {
    if (_planUpgradeInProgress) return;

    setState(() => _planUpgradeInProgress = true);

    try {
      final ok =
          await LeaguePremiumUpgradeHelper.openUpgradeFlow(
        context,
        leagueName: 'Organizer Plan',
      );

      if (!mounted) return;

      if (ok) {
        _snack('Plan purchase completed. Refreshing access...');
        await _refreshLeagues();
        return;
      }

      _snack('Plan upgrade cancelled.');
    } catch (e) {
      if (!mounted) return;
      _snack(UserFriendlyError.toMessage(
          e is Object ? e : Exception('unknown')));
    } finally {
      if (mounted) {
        setState(() => _planUpgradeInProgress = false);
      }
    }
  }

  Future<List<League>> _fetchLeaguesFromFirestoreForWeb(
      String uid) async {
    final trimmed = uid.trim();
    if (trimmed.isEmpty) return [];

    final ids = <String>{};
    final Map<String, Map<String, dynamic>> docsById = {};

    try {
      final snap = await _firestore
          .collection('leagues')
          .where('memberIds', arrayContains: trimmed)
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 20));

      for (final doc in snap.docs) {
        if (ids.add(doc.id)) {
          docsById[doc.id] = doc.data();
        }
      }
    } catch (e) {
      debugPrint('[LeaguesListScreen] web memberIds query failed: $e');
    }

    try {
      final snap = await _firestore
          .collection('leagues')
          .where('organizerUid', isEqualTo: trimmed)
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 20));

      for (final doc in snap.docs) {
        if (ids.add(doc.id)) {
          docsById[doc.id] = doc.data();
        }
      }
    } catch (e) {
      debugPrint('[LeaguesListScreen] web organizerUid query failed: $e');
    }

    try {
      final snap = await _firestore
          .collection('leagues')
          .where('ownerUid', isEqualTo: trimmed)
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 20));

      for (final doc in snap.docs) {
        if (ids.add(doc.id)) {
          docsById[doc.id] = doc.data();
        }
      }
    } catch (e) {
      debugPrint('[LeaguesListScreen] web ownerUid query failed: $e');
    }

    if (_looksLikeFirebaseUid(trimmed)) {
      try {
        final snap = await _firestore
            .collection('leagues')
            .where('ownerId', isEqualTo: trimmed)
            .get(const GetOptions(source: Source.server))
            .timeout(const Duration(seconds: 20));

        for (final doc in snap.docs) {
          if (ids.add(doc.id)) {
            docsById[doc.id] = doc.data();
          }
        }
      } catch (e) {
        debugPrint('[LeaguesListScreen] web ownerId query failed: $e');
      }
    }

    if (_looksLikeFirebaseUid(trimmed)) {
      try {
        final snap = await _firestore
            .collection('leagues')
            .where('organizerUserId', isEqualTo: trimmed)
            .get(const GetOptions(source: Source.server))
            .timeout(const Duration(seconds: 20));

        for (final doc in snap.docs) {
          if (ids.add(doc.id)) {
            docsById[doc.id] = doc.data();
          }
        }
      } catch (e) {
        debugPrint(
            '[LeaguesListScreen] web organizerUserId query failed: $e');
      }
    }

    if (docsById.isEmpty) return [];

    final leagues = <League>[];
    for (final entry in docsById.entries) {
      try {
        final data = entry.value;
        data['id'] = entry.key;
        final map = <String, dynamic>{...data}; 
        final existingId = (map['id'] as String?)?.trim() ?? ''; 
        if (existingId.isEmpty) map['id'] = entry.key; 
        final league = League.fromRemoteMap(map);
        leagues.add(league);
      } catch (e) {
        debugPrint(
            '[LeaguesListScreen] failed to parse league ${entry.key}: $e');
      }
    }

    return leagues;
  }

  Future<List<Membership>> _fetchMembershipsFromFirestoreForWeb(
      String uid, List<League> leagues) async {
    final trimmed = uid.trim();
    if (trimmed.isEmpty || leagues.isEmpty) return [];

    final memberships = <Membership>[];

    await Future.wait(
      leagues.map((league) async {
        try {
          final doc = await _firestore
              .collection('leagues')
              .doc(league.id)
              .collection('memberships')
              .doc(trimmed)
              .get(const GetOptions(source: Source.server))
              .timeout(const Duration(seconds: 10));

          if (doc.exists && doc.data() != null) {
            final data = doc.data()!;
            data['id'] = doc.id;
            try {
              final map = <String, dynamic>{...data}; 
              final existingId = (map['id'] as String?)?.trim() ?? ''; 
              if (existingId.isEmpty) map['id'] = (map['id'] as String?)?.trim().isNotEmpty == true ? map['id'] : ''; 
              memberships.add(Membership.fromRemoteMap(map));
            } catch (_) {}
          }
        } catch (_) {}
      }),
    );

    return memberships;
  }

  Future<void> _loadLeagues({required bool showSpinner}) async {
    if (showSpinner && mounted) {
      setState(() => _isLoading = true);
    }

    try {
      final effectiveUserId = _authUidOrEmpty();
      if (effectiveUserId.isEmpty) {
        throw FirebaseAuthException(code: 'unauthenticated');
      }

      final premium =
          await _detectPremiumUser(effectiveUserId);
      final hasLeagueAccess =
          await _detectLeagueAccessFromPlan(effectiveUserId);
      final createdCount =
          await _countCreatedLeaguesAcrossAllFlows(effectiveUserId);

      List<League> leagues;
      List<Membership> memberships;

      if (kIsWeb) {
        leagues = await _fetchLeaguesFromFirestoreForWeb(effectiveUserId);
        memberships = await _fetchMembershipsFromFirestoreForWeb(
            effectiveUserId, leagues);
      } else {
        leagues = await _repo
            .listLeagues()
            .timeout(const Duration(seconds: 20));
        memberships = await _repo
            .listMemberships()
            .timeout(const Duration(seconds: 25));
      }

      final Map<String, int> counts = {};
      final Map<String, bool> viewerIsParticipant = {};
      final Map<String, bool> viewerUnlocked = {};

      await Future.wait(
        leagues.map((league) async {
          final registered =
              await _countParticipantsRemote(league.id);
          counts[league.id] = registered;

          final isParticipant = memberships.any(
            (m) =>
                m.leagueId == league.id &&
                m.userId == effectiveUserId &&
                (m.role == LeagueRole.member ||
                    m.role == LeagueRole.organizer),
          );
          viewerIsParticipant[league.id] = isParticipant;

          final isOwner =
              _isOwnerForViewer(league, effectiveUserId);

          final requiresPaidLeague =
              league.format == LeagueFormat.uclGroup ||
                  league.format == LeagueFormat.uclSwiss;

          final isClassic =
              league.format == LeagueFormat.classic;
          final isFull = registered >= league.maxTeams;

          final classicFullViewerRequiresUnlock =
              isClassic &&
                  isFull &&
                  !isOwner &&
                  !isParticipant;

          if (isOwner) {
            viewerUnlocked[league.id] = true;
            return;
          }

          if (isClassic && isParticipant) {
            viewerUnlocked[league.id] = true;
            return;
          }

          if (!requiresPaidLeague &&
              !classicFullViewerRequiresUnlock) {
            viewerUnlocked[league.id] = true;
            return;
          }

          final paidReceipt = await _hasPaidChargesRemote(
            userId: effectiveUserId,
            leagueId: league.id,
          ).timeout(const Duration(seconds: 12));

          final paidCoupon = paidReceipt
              ? false
              : await _hasPaidCouponRemote(
                  userId: effectiveUserId,
                  leagueId: league.id,
                ).timeout(const Duration(seconds: 12));

          viewerUnlocked[league.id] =
              paidReceipt || paidCoupon;
        }),
      );

      if (!mounted) return;

      setState(() {
        _leagues = leagues;
        _participantCounts = counts;
        _viewerChargesPaid = viewerUnlocked;
        _viewerIsParticipantByLeagueId = viewerIsParticipant;
        _effectiveUserId = effectiveUserId;
        _isPremiumUser = premium;
        _hasLeagueAccess = hasLeagueAccess;
        _createdLeagueCount = createdCount;
        _checkingPlan = false;
        _isLoading = false;
      });

      if (!premium) {
        unawaited(
          RewardedAdManager.instance
              .preload(placement: 'view_league'),
        );
      }

      unawaited(_loadLatestAnnouncements(leagues));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _checkingPlan = false;
        _isLoading = false;
      });
      _snack(
        UserFriendlyError.toMessage(
            e is Object ? e : Exception('unknown')),
      );
    }
  }

  Future<void> _loadLatestAnnouncements(
      List<League> leagues) async {
    if (_loadingAnnouncements) return;
    _loadingAnnouncements = true;

    try {
      final Map<String, LeagueAnnouncement?> latestAnns = {};

      await Future.wait(leagues.map((league) async {
        try {
          final snap = await _firestore
              .collection('leagues')
              .doc(league.id)
              .collection('announcements')
              .orderBy('createdAtMs', descending: true)
              .limit(1)
              .get(const GetOptions(source: Source.server))
              .timeout(const Duration(seconds: 6));

          if (snap.docs.isEmpty) return;
          latestAnns[league.id] =
              LeagueAnnouncement.fromMap(
                  snap.docs.first.data());
        } catch (_) {}
      }));

      if (!mounted) return;
      setState(() => _latestAnnouncements = latestAnns);
    } finally {
      _loadingAnnouncements = false;
    }
  }

  Future<void> _refreshLeagues() async {
    await _loadLeagues(showSpinner: true);
  }

  DocumentReference<Map<String, dynamic>> _leagueRef(
          String leagueId) =>
      _firestore.collection('leagues').doc(leagueId);

  CollectionReference<Map<String, dynamic>>
      _membershipsCol(String leagueId) =>
          _leagueRef(leagueId).collection('memberships');

  Future<int> _countParticipantsRemote(
      String leagueId) async {
    final snap = await _membershipsCol(leagueId)
        .get(const GetOptions(source: Source.server))
        .timeout(const Duration(seconds: 12));

    var count = 0;
    for (final d in snap.docs) {
      final data = d.data();
      final uid =
          (data['userId'] as String?)?.trim() ?? '';
      final roleIdx = (data['role'] as num?)?.toInt();
      final isParticipantRole =
          roleIdx == LeagueRole.organizer.index ||
              roleIdx == LeagueRole.member.index;
      if (uid.isNotEmpty && isParticipantRole) {
        count++;
      }
    }
    return count;
  }

  Future<bool> _hasPaidChargesRemote({
    required String userId,
    required String leagueId,
  }) async {
    final uid = userId.trim();
    if (uid.isEmpty) return false;

    final doc = await _firestore
        .collection('users')
        .doc(uid)
        .collection('leagueCharges')
        .doc(leagueId)
        .get(const GetOptions(source: Source.server));

    if (!doc.exists) return false;

    final data = doc.data() ?? <String, dynamic>{};
    final paidFlag = data['paid'] == true;
    final receiptId =
        (data['receiptId'] ?? '').toString().trim();
    final paidAtMs = (data['paidAtMs'] is num)
        ? (data['paidAtMs'] as num).toInt()
        : 0;

    return paidFlag || receiptId.isNotEmpty || paidAtMs > 0;
  }

  Future<bool> _hasPaidCouponRemote({
    required String userId,
    required String leagueId,
  }) async {
    final uid = userId.trim();
    if (uid.isEmpty) return false;

    final snap = await _firestore
        .collection('leagues')
        .doc(leagueId)
        .collection('couponRedemptions')
        .doc(uid)
        .get(const GetOptions(source: Source.server))
        .timeout(const Duration(seconds: 10));

    if (!snap.exists) return false;

    final data = snap.data() ?? <String, dynamic>{};
    final status =
        (data['status'] ?? '').toString().trim().toLowerCase();
    final paidAtMs = (data['paidAtMs'] is num)
        ? (data['paidAtMs'] as num).toInt()
        : 0;

    if (status == 'paid') return true;
    if (status.isEmpty && paidAtMs > 0) return true;

    return false;
  }

  Future<void> _handleLeagueCardDoubleTap(
      League league) async {
    if (_rewardGateInProgress) return;

    if (_isPremiumUser) {
      context.push('/leagues/${league.id}');
      return;
    }

    if (kIsWeb) {
      context.push('/leagues/${league.id}');
      return;
    }

    setState(() => _rewardGateInProgress = true);

    bool rewardEarned = false;

    try {
      rewardEarned =
          await RewardedAdManager.instance.showRewardedGate(
        placement: 'view_league',
      );
    } finally {
      if (mounted) {
        setState(() => _rewardGateInProgress = false);
      }
    }

    if (!mounted) return;

    if (!rewardEarned) {
      _snack(
        'Watch the full ad to open league details. '
        'Please try again.',
      );
      return;
    }

    context.push('/leagues/${league.id}');
  }

  Future<void> _showLeagueLongPressMenu(
    BuildContext context,
    League league,
  ) async {
    final authUid = _authUidOrEmpty();
    final isOwner = _isOwnerForViewer(league, authUid);
    final brightness = Theme.of(context).brightness;

    if (isOwner) {
      _snack(
        'League owners should manage their league from '
        'the owner/admin area.',
      );
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        final theme = Theme.of(sheetCtx);

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Center(
              child: ConstrainedBox(
                constraints:
                    const BoxConstraints(maxWidth: 540),
                child: Glass(
                  borderRadius: 26,
                  padding: const EdgeInsets.all(16),
                  fill: AppTheme.cardColor(brightness),
                  borderColor:
                      AppTheme.cardBorder(brightness),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 40,
                        height: 4,
                        margin: const EdgeInsets.only(
                            bottom: 14),
                        decoration: BoxDecoration(
                          color:
                              AppTheme.cardBorder(brightness),
                          borderRadius:
                              BorderRadius.circular(2),
                        ),
                      ),
                      Text(
                        league.name,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleMedium
                            ?.copyWith(
                          fontWeight: FontWeight.w900,
                          color: AppTheme.primaryText(
                              brightness),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        league.isInsideMasterLeague
                            ? 'This competition belongs to a '
                              'master league workspace. You can '
                              'still remove it from your '
                              'personal list.'
                            : 'You can remove this league from '
                              'your list if you no longer need '
                              'it.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(
                          color: AppTheme.secondaryText(
                              brightness),
                          fontWeight: FontWeight.w700,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            Navigator.of(sheetCtx).pop();
                            await _leaveLeague(league);
                          },
                          icon: const Icon(
                              Icons.exit_to_app_rounded),
                          label: const Text(
                            'Remove from My List',
                            style: TextStyle(
                                fontWeight: FontWeight.w900),
                          ),
                        ),
                      ),
                      if (league.isInsideMasterLeague &&
                          league.masterLeagueId
                              .trim()
                              .isNotEmpty) ...[
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.tonalIcon(
                            onPressed: () {
                              Navigator.of(sheetCtx).pop();
                              context.push(
                                '/master-leagues/'
                                '${league.masterLeagueId}',
                              );
                            },
                            icon: const Icon(
                                Icons.hub_rounded),
                            label: const Text(
                              'Open Workspace',
                              style: TextStyle(
                                  fontWeight:
                                      FontWeight.w900),
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: TextButton(
                          onPressed: () =>
                              Navigator.of(sheetCtx).pop(),
                          child: const Text(
                            'Cancel',
                            style: TextStyle(
                                fontWeight: FontWeight.w900),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _leaveLeague(League league) async {
    final brightness = Theme.of(context).brightness;

    final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) {
            final theme = Theme.of(ctx);

            return Dialog(
              backgroundColor: Colors.transparent,
              child: Glass(
                borderRadius: 24,
                padding: const EdgeInsets.all(18),
                fill: AppTheme.cardColor(brightness),
                borderColor: AppTheme.cardBorder(brightness),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.exit_to_app_rounded,
                      color: AppTheme.limeAccentDark,
                      size: 34,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Remove league from your list?',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleMedium
                          ?.copyWith(
                        fontWeight: FontWeight.w900,
                        color:
                            AppTheme.primaryText(brightness),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'You will leave "${league.name}" and it '
                      'will no longer appear on your leagues '
                      'screen.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(
                        color: AppTheme.secondaryText(
                            brightness),
                        fontWeight: FontWeight.w700,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () =>
                                Navigator.of(ctx).pop(false),
                            child: const Text(
                              'Cancel',
                              style: TextStyle(
                                  fontWeight: FontWeight.w900),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor:
                                  AppTheme.limeAccent,
                              foregroundColor:
                                  AppTheme.darkText,
                            ),
                            onPressed: () =>
                                Navigator.of(ctx).pop(true),
                            child: const Text(
                              'Remove',
                              style: TextStyle(
                                  fontWeight: FontWeight.w900),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        ) ??
        false;

    if (!confirmed) return;

    if (mounted) {
      setState(() => _removingLeagueId = league.id);
    }

    try {
      if (kIsWeb) {
        final uid = _authUidOrEmpty();
        if (uid.isNotEmpty) {
          await _firestore
              .collection('leagues')
              .doc(league.id)
              .update({
            'memberIds': FieldValue.arrayRemove([uid]),
            'updatedAtMs':
                DateTime.now().millisecondsSinceEpoch,
          });
        }
      } else {
        await _repo.leaveLeague(league.id);
      }

      if (!mounted) return;
      _snack('League removed from your list.');
      await _refreshLeagues();
    } catch (e) {
      if (!mounted) return;
      _snack(
        UserFriendlyError.toMessage(
            e is Object ? e : Exception('unknown')),
      );
    } finally {
      if (mounted) {
        setState(() => _removingLeagueId = null);
      }
    }
  }

  Future<void> _payChargesForLeague(
    BuildContext context,
    League league,
  ) async {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final brightness = theme.brightness;

    if (_payingLeagueId == league.id) return;

    final authUid = _authUidOrEmpty();
    if (authUid.isEmpty) {
      _snack('Please sign in and try again.');
      return;
    }

    final registered =
        _participantCounts[league.id] ?? 0;
    final isFull = registered >= league.maxTeams;

    final isOwner = _isOwnerForViewer(league, authUid);
    final viewerIsParticipant =
        _viewerIsParticipantByLeagueId[league.id] ?? false;

    final requiresPaidLeague =
        league.format == LeagueFormat.uclGroup ||
            league.format == LeagueFormat.uclSwiss;
    final isClassic =
        league.format == LeagueFormat.classic;

    final classicFullViewerRequiresUnlock =
        isClassic && isFull && !isOwner && !viewerIsParticipant;

    if (!requiresPaidLeague &&
        !classicFullViewerRequiresUnlock) return;

    if (isOwner) {
      _snack(l10n.tr('leagues_creator_unlocked'));
      return;
    }

    final alreadyPaid = await _hasPaidChargesRemote(
      userId: authUid,
      leagueId: league.id,
    );
    final alreadyCoupon = alreadyPaid
        ? false
        : await _hasPaidCouponRemote(
            userId: authUid,
            leagueId: league.id,
          );

    if (alreadyPaid || alreadyCoupon) {
      if (!mounted) return;
      setState(
          () => _viewerChargesPaid[league.id] = true);
      return;
    }

    final couponCtrl = TextEditingController();
    bool busy = false;
    String? error;

    String normalizeCoupon(String raw) {
      return raw
          .trim()
          .toUpperCase()
          .replaceAll(' ', '')
          .replaceAll('-', '')
          .replaceAll(RegExp(r'[^A-Z0-9_%]'), '');
    }

    Future<void> unlockByPay(
        StateSetter setModalState) async {
      if (busy) return;

      setModalState(() {
        busy = true;
        error = null;
      });
      setState(() => _payingLeagueId = league.id);

      try {
        final paymentService =
            ref.read(leagueChargesPaymentServiceProvider);

        final result =
            await paymentService.payLeagueCharges(
          context: context,
          userId: authUid,
          leagueId: league.id,
          leagueName: league.name,
        );

        if (!mounted) return;

        if (!result.success) {
          setModalState(() {
            busy = false;
            error =
                result.errorMessage?.trim().isNotEmpty == true
                    ? result.errorMessage
                    : l10n.tr('leagues_payment_failed');
          });
          setState(() => _payingLeagueId = null);
          return;
        }

        await LeagueChargesStore.online().storeReceipt(
          LeagueChargesReceipt(
            leagueId: league.id,
            userId: authUid,
            receiptId:
                result.receiptId ?? 'FLW-UNKNOWN',
            provider: result.provider,
            paidAtMs: result.paidAtMs,
          ),
        );

        await LeagueAccessService.instance
            .ensureDeterministicMembershipBestEffort(
          leagueId: league.id,
          uid: authUid,
        );

        if (!mounted) return;
        setState(() {
          _payingLeagueId = null;
          _viewerChargesPaid[league.id] = true;
        });

        Navigator.of(context).pop();
        _snack(l10n.tr('leagues_unlocked_success'));
      } catch (e) {
        if (!mounted) return;
        setModalState(() {
          busy = false;
          error = UserFriendlyError.toMessage(
            e is Object ? e : Exception('unknown'),
          );
        });
        setState(() => _payingLeagueId = null);
      }
    }

    Future<void> unlockByCoupon(
        StateSetter setModalState) async {
      if (busy) return;

      final code =
          normalizeCoupon(couponCtrl.text);
      if (code.length < 6) {
        setModalState(
            () => error = 'Enter a valid coupon code.');
        return;
      }

      setModalState(() {
        busy = true;
        error = null;
      });
      setState(() => _payingLeagueId = league.id);

      try {
        final res =
            await CouponCodesService().redeemWithCode(
          context: context,
          leagueId: league.id,
          leagueName: league.name,
          userId: authUid,
          code: code,
        );

        if (!mounted) return;

        if (!res.success) {
          setModalState(() {
            busy = false;
            error =
                res.errorMessage?.trim().isNotEmpty == true
                    ? res.errorMessage
                    : 'Coupon redemption failed.';
          });
          setState(() => _payingLeagueId = null);
          return;
        }

        await LeagueAccessService.instance
            .ensureDeterministicMembershipBestEffort(
          leagueId: league.id,
          uid: authUid,
        );
      } catch (_) {}

      try {
        await LeagueAccessService.instance
            .ensureDeterministicMembershipBestEffort(
          leagueId: league.id,
          uid: authUid,
        );
      } catch (_) {}

      if (!mounted) return;
      setState(() {
        _payingLeagueId = null;
        _viewerChargesPaid[league.id] = true;
      });

      Navigator.of(context).pop();
      _snack('Coupon redeemed. Access unlocked.');
    }

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetCtx) {
        final bottomInset =
            MediaQuery.of(sheetCtx).viewInsets.bottom;

        return SafeArea(
          child: Padding(
            padding: EdgeInsets.only(bottom: bottomInset)
                .add(const EdgeInsets.all(12)),
            child: Center(
              child: ConstrainedBox(
                constraints:
                    const BoxConstraints(maxWidth: 560),
                child: Glass(
                  borderRadius: 28,
                  fill: AppTheme.cardColor(brightness),
                  borderColor:
                      AppTheme.cardBorder(brightness),
                  child: StatefulBuilder(
                    builder: (ctx, setModalState) {
                      return Padding(
                        padding: const EdgeInsets.all(18),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 40,
                              height: 4,
                              margin: const EdgeInsets.only(
                                  bottom: 16),
                              decoration: BoxDecoration(
                                color: AppTheme.cardBorder(
                                    brightness),
                                borderRadius:
                                    BorderRadius.circular(
                                        2),
                              ),
                            ),
                            Text(
                              'Unlock access',
                              style: theme
                                  .textTheme.titleMedium
                                  ?.copyWith(
                                fontWeight: FontWeight.w900,
                                fontSize: 18,
                                color: AppTheme.primaryText(
                                    brightness),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              league.name,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color:
                                    AppTheme.secondaryText(
                                        brightness),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            if (classicFullViewerRequiresUnlock) ...[
                              const SizedBox(height: 10),
                              Text(
                                'This classic league is full. '
                                'You can unlock access as a '
                                'viewer by paying or using a '
                                'coupon.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color:
                                      AppTheme.secondaryText(
                                          brightness),
                                  fontSize: 12,
                                  height: 1.35,
                                  fontWeight:
                                      FontWeight.w600,
                                ),
                              ),
                            ],
                            const SizedBox(height: 16),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton.icon(
                                style:
                                    FilledButton.styleFrom(
                                  backgroundColor:
                                      AppTheme.limeAccent,
                                  foregroundColor:
                                      AppTheme.darkText,
                                ),
                                onPressed: busy
                                    ? null
                                    : () => unlockByPay(
                                        setModalState),
                                icon: busy
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child:
                                            CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color:
                                              AppTheme.darkText,
                                        ),
                                      )
                                    : const Icon(Icons
                                        .payments_outlined),
                                label: busy
                                    ? const Text('')
                                    : const Text(
                                        'Pay to unlock',
                                        style: TextStyle(
                                          fontWeight:
                                              FontWeight.w900,
                                        ),
                                      ),
                              ),
                            ),
                            const SizedBox(height: 14),
                            Align(
                              alignment:
                                  AlignmentDirectional
                                      .centerStart,
                              child: Text(
                                'Or use a coupon',
                                style: TextStyle(
                                  color:
                                      AppTheme.primaryText(
                                          brightness),
                                  fontWeight: FontWeight.w900,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: couponCtrl,
                              enabled: !busy,
                              textCapitalization:
                                  TextCapitalization.characters,
                              decoration:
                                  const InputDecoration(
                                prefixIcon: Icon(Icons
                                    .confirmation_number_outlined),
                                hintText:
                                    'Enter coupon code',
                              ),
                              onSubmitted: (_) =>
                                  unlockByCoupon(
                                      setModalState),
                            ),
                            const SizedBox(height: 10),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: busy
                                    ? null
                                    : () => unlockByCoupon(
                                        setModalState),
                                icon: const Icon(Icons
                                    .verified_outlined),
                                label: const Text(
                                  'Apply coupon',
                                  style: TextStyle(
                                      fontWeight:
                                          FontWeight.w900),
                                ),
                              ),
                            ),
                            if ((error ?? '')
                                .trim()
                                .isNotEmpty) ...[
                              const SizedBox(height: 12),
                              Container(
                                width: double.infinity,
                                padding:
                                    const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .error
                                      .withOpacity(0.10),
                                  borderRadius:
                                      BorderRadius.circular(
                                          14),
                                  border: Border.all(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .error
                                        .withOpacity(0.25),
                                  ),
                                ),
                                child: Text(
                                  error!.trim(),
                                  style: TextStyle(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .error,
                                    fontWeight:
                                        FontWeight.w800,
                                  ),
                                ),
                              ),
                            ],
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              child: TextButton(
                                onPressed: busy
                                    ? null
                                    : () => Navigator.of(ctx)
                                        .pop(),
                                child: Text(
                                    l10n.tr('common_cancel')),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );

    couponCtrl.dispose();
    if (mounted) setState(() => _payingLeagueId = null);
  }

  Future<void> _handleCreateLeagueTap(
      BuildContext context) async {
    if (_checkingPlan) {
      _snack('Checking your access. Please wait.');
      return;
    }

    if (!_hasLeagueAccess) {
      await _openInlinePlanChooser();
      return;
    }

    if (_freeLimitReached) {
      await _openInlinePlanChooser();
      return;
    }

    await context.push('/leagues/create');
    if (mounted) {
      await _refreshLeagues();
    }
  }

  Future<void> _handleJoinQrTap(
      BuildContext context) async {
    if (_checkingPlan) {
      _snack('Checking your access. Please wait.');
      return;
    }

    await context.push('/leagues/join-scanner');
    if (mounted) {
      await _refreshLeagues();
    }
  }

  Future<void> _handleJoinByIdTap(
      BuildContext context) async {
    if (_checkingPlan) {
      _snack('Checking your access. Please wait.');
      return;
    }

    await _showJoinByIdSheet(context);
    if (mounted) {
      await _refreshLeagues();
    }
  }

  List<League> _filteredLeagues() {
    final q = _searchQuery.trim().toLowerCase();

    var base = _selectedTab == _LeagueViewTab.leagues
        ? _leagues.where((l) => !l.isInsideMasterLeague).toList()
        : _leagues.where((l) => l.isInsideMasterLeague).toList();

    final catFilter = _categoryFilter;
    if (catFilter != null) {
      base = base.where((l) => l.footballCategory == catFilter).toList();
    }

    if (q.isEmpty) return base;

    return base.where((league) {
      final latestAnn = _latestAnnouncements[league.id];
      final haystack = <String>[
        league.name,
        league.region,
        league.season,
        league.description,
        league.code,
        league.masterLeagueId,
        league.footballCategory.badgeLabel,
        latestAnn?.title ?? '',
        latestAnn?.message ?? '',
      ].join(' ').toLowerCase();

      return haystack.contains(q);
    }).toList();
  }

  String _buildCardSubtitle({
    required BuildContext context,
    required League league,
    required int registered,
    required LeagueAnnouncement? latestAnn,
  }) {
    final l10n = context.l10n;
    final pieces = <String>[
      '$registered / ${league.maxTeams} '
          '${l10n.tr('leagues_teams_word')}',
    ];

    if (league.viewerCapacity > 0) {
      pieces.add('${league.viewerCapacity} Viewers');
    }

    final desc = league.description.trim();
    if (desc.isNotEmpty) {
      pieces.add(desc);
    }

    if (latestAnn != null &&
        latestAnn.title.trim().isNotEmpty) {
      pieces.add(latestAnn.title.trim());
    }

    return pieces.join(' • ');
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final l10n = context.l10n;
    final theme = Theme.of(context);
    final brightness = theme.brightness;

    final media = MediaQuery.of(context);
    final screenWidth = media.size.width;
    final isTablet = screenWidth >= 600;
    final fabBottomOffset =
        kBottomNavigationBarHeight + media.padding.bottom + 16;

    final filtered = _filteredLeagues();
    final normalCount =
        _leagues.where((l) => !l.isInsideMasterLeague).length;
    final masterCount =
        _leagues.where((l) => l.isInsideMasterLeague).length;

    final bool isAndroidBilling = PaymentPlatformConfig
        .routeAndroidPaymentsToGooglePlayBilling;

    return GlassScaffold(
      resizeToAvoidBottomInset: true,
      appBar: widget.showAppBar
          ? AppBar(
              title: const Text('Leagues'),
              backgroundColor: Colors.transparent,
              elevation: 0,
              centerTitle: false,
              toolbarHeight: 50,
              actions: [
                IconButton(
                  tooltip: l10n.tr('common_refresh'),
                  icon: const Icon(Icons.refresh_rounded),
                  onPressed: _refreshLeagues,
                ),
              ],
            )
          : null,
      floatingActionButton: Padding(
        padding:
            EdgeInsets.only(bottom: fabBottomOffset),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            boxShadow: AppTheme.fabGlow(brightness),
          ),
          child: FloatingActionButton(
            onPressed: () => _showOptions(context),
            backgroundColor: _freeLimitReached
                ? _premiumAmber
                : AppTheme.limeAccent,
            foregroundColor: _freeLimitReached
                ? Colors.black
                : AppTheme.darkText,
            child: Icon(
              _freeLimitReached
                  ? Icons.workspace_premium_rounded
                  : Icons.add_rounded,
            ),
          ),
        ),
      ),
      floatingActionButtonLocation:
          FloatingActionButtonLocation.endFloat,
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
                maxWidth: isTablet ? 900 : 600),
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    16,
                    widget.showAppBar ? 2 : 8,
                    16,
                    0,
                  ),
                  child: Glass(
                    borderRadius: 18,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    fill: AppTheme.cardColor(brightness),
                    borderColor:
                        AppTheme.cardBorder(brightness),
                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment:
                              CrossAxisAlignment.center,
                          children: [
                            Container(
                              width: 38,
                              height: 38,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: AppTheme
                                    .iconCircleBackground(
                                        brightness),
                              ),
                              child: Icon(
                                Icons.emoji_events_rounded,
                                color:
                                    AppTheme.limeAccentDark,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    l10n.tr(
                                        'leagues_my_leagues_title'),
                                    style: theme.textTheme
                                        .titleMedium
                                        ?.copyWith(
                                      fontWeight:
                                          FontWeight.w900,
                                      fontSize: 17,
                                      letterSpacing: -0.3,
                                      color:
                                          AppTheme.primaryText(
                                              brightness),
                                    ),
                                  ),
                                  const SizedBox(height: 1),
                                  Text(
                                    _isLoading
                                        ? 'Loading...'
                                        : '${_leagues.length} league'
                                          '${_leagues.length == 1 ? '' : 's'}',
                                    style: TextStyle(
                                      color: AppTheme
                                          .secondaryText(
                                              brightness),
                                      fontSize: 11.5,
                                      fontWeight:
                                          FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (!widget.showAppBar)
                              IconButton(
                                tooltip:
                                    l10n.tr('common_refresh'),
                                visualDensity:
                                    VisualDensity.compact,
                                onPressed: _refreshLeagues,
                                icon: const Icon(
                                    Icons.refresh_rounded),
                              ),
                          ],
                        ),
                        if (!_isLoading) ...[
                          const SizedBox(height: 8),
                          if (_checkingPlan)
                            Text(
                              'Checking your access...',
                              style: TextStyle(
                                color: AppTheme.secondaryText(
                                    brightness),
                                fontSize: 11.5,
                                fontWeight: FontWeight.w800,
                                height: 1.28,
                              ),
                            )
                          else if (_isPremiumUser)
                            Text(
                              'Paid plan active: you can create '
                              'more than $_freeLeagueListLimit '
                              'leagues/competitions.',
                              style: TextStyle(
                                color:
                                    AppTheme.limeAccentDark,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w800,
                                height: 1.28,
                              ),
                            )
                          else if (_freeLimitReached)
                            Text(
                              'Basic/free creation limit '
                              'reached: you already created '
                              '$_createdLeagueCount / '
                              '$_freeLeagueListLimit leagues '
                              'or competitions across normal '
                              'leagues and Organizer workspace.',
                              style: const TextStyle(
                                color: _premiumAmber,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w800,
                                height: 1.28,
                              ),
                            )
                          else
                            Text(
                              'Basic/free access active: you '
                              'have used $_createdLeagueCount '
                              '/ $_freeLeagueListLimit shared '
                              'creation slots across normal '
                              'leagues and Organizer workspace.',
                              style: TextStyle(
                                color: AppTheme.secondaryText(
                                    brightness),
                                fontSize: 11.5,
                                fontWeight: FontWeight.w800,
                                height: 1.28,
                              ),
                            ),
                          const SizedBox(height: 8),
                          SizedBox(
                            width: double.infinity,
                            height: 42,
                            child: FilledButton.icon(
                              onPressed: _planUpgradeInProgress
                                  ? null
                                  : _openInlinePlanChooser,
                              style: FilledButton.styleFrom(
                                backgroundColor:
                                    _freeLimitReached
                                        ? _premiumAmber
                                        : AppTheme.limeAccent,
                                foregroundColor:
                                    AppTheme.darkText,
                                padding:
                                    const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                              ),
                              icon: _planUpgradeInProgress
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child:
                                          CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: AppTheme.darkText,
                                      ),
                                    )
                                  : Icon(
                                      isAndroidBilling
                                          ? Icons
                                              .shopping_bag_outlined
                                          : Icons
                                              .payments_outlined,
                                      size: 18,
                                    ),
                              label: Text(
                                _planUpgradeInProgress
                                    ? 'Processing...'
                                    : (_freeLimitReached
                                        ? (isAndroidBilling
                                            ? 'Upgrade on Play'
                                            : 'Upgrade Plan')
                                        : (isAndroidBilling
                                            ? 'View Plans (Play)'
                                            : 'View Plans')),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16),
                  child: Glass(
                    borderRadius: 18,
                    padding: EdgeInsets.zero,
                    fill: AppTheme.searchBackground(brightness),
                    borderColor:
                        AppTheme.searchOutline(brightness),
                    child: Row(
                      children: [
                        const SizedBox(width: 12),
                        Icon(
                          Icons.search_rounded,
                          size: 19,
                          color: AppTheme.secondaryText(
                              brightness),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _searchController,
                            decoration:
                                const InputDecoration(
                              hintText:
                                  'Search leagues, codes, '
                                  'announcements...',
                              border: InputBorder.none,
                              isDense: true,
                            ),
                          ),
                        ),
                        if (_searchQuery.trim().isNotEmpty)
                          IconButton(
                            tooltip: 'Clear',
                            visualDensity:
                                VisualDensity.compact,
                            onPressed: () {
                              _searchController.clear();
                            },
                            icon: const Icon(
                                Icons.close_rounded),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16),
                  child: _TopLeagueSwitcher(
                    selectedTab: _selectedTab,
                    normalCount: normalCount,
                    masterCount: masterCount,
                    onChanged: (tab) {
                      if (_selectedTab == tab) return;
                      setState(() => _selectedTab = tab);
                    },
                  ),
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _FilterChip(
                          label: 'All',
                          selected: _categoryFilter == null,
                          onTap: () => setState(
                              () => _categoryFilter = null),
                        ),
                        for (final cat
                            in FootballCategoryUtil.all) ...[
                          const SizedBox(width: 8),
                          _FilterChip(
                            label: cat.badgeLabel,
                            selected: _categoryFilter == cat,
                            onTap: () => setState(
                                () => _categoryFilter = cat),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Expanded(
                  child: AnimatedSwitcher(
                    duration:
                        const Duration(milliseconds: 200),
                    child: _isLoading
                        ? Center(
                            child: Column(
                              mainAxisSize:
                                  MainAxisSize.min,
                              children: [
                                CircularProgressIndicator(
                                  color:
                                      AppTheme.limeAccentDark,
                                ),
                                const SizedBox(height: 14),
                                Text(
                                  'Loading leagues...',
                                  style: TextStyle(
                                    color:
                                        AppTheme.secondaryText(
                                            brightness),
                                    fontWeight:
                                        FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : filtered.isEmpty
                            ? _buildEmptyState(context)
                            : _buildLeagueGrid(
                                context,
                                filtered,
                                isTablet,
                              ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLeagueGrid(
    BuildContext context,
    List<League> leagues,
    bool isTablet,
  ) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final brightness = theme.brightness;

    final viewerUid = _effectiveUserId.trim();
    final authUid = _authUidOrEmpty();

    final cardHeight = isTablet ? 250.0 : 250.0;
    final showWorkspaceAction =
        _selectedTab == _LeagueViewTab.master;
    final extraActionHeight =
        showWorkspaceAction ? 52.0 : 0.0;
    final mainAxisExtent = cardHeight + extraActionHeight;

    return GridView.builder(
      shrinkWrap: true,
      itemCount: leagues.length,
      keyboardDismissBehavior:
          ScrollViewKeyboardDismissBehavior.onDrag,
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      padding: EdgeInsets.fromLTRB(
        16,
        8,
        16,
        16 +
            MediaQuery.of(context).padding.bottom +
            kBottomNavigationBarHeight +
            80,
      ),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: isTablet ? 2 : 1,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
        mainAxisExtent: mainAxisExtent,
      ),
      itemBuilder: (context, index) {
        final league = leagues[index];

        final bool isOwner = _isOwnerForViewer(
          league,
          authUid.isNotEmpty ? authUid : viewerUid,
        );
        final bool viewerIsParticipant =
            _viewerIsParticipantByLeagueId[league.id] ??
                false;
        final bool viewerIsViewerOnly =
            !isOwner && !viewerIsParticipant;

        final registered =
            _participantCounts[league.id] ?? 0;
        final isFull = registered >= league.maxTeams;

        final latestAnn =
            _latestAnnouncements[league.id];
        final subtitle = _buildCardSubtitle(
          context: context,
          league: league,
          registered: registered,
          latestAnn: latestAnn,
        );

        final removingThis =
            _removingLeagueId == league.id;

        return Column(
          crossAxisAlignment:
              CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Opacity(
                opacity: removingThis ? 0.65 : 1,
                child: Stack(
                  children: [
                    GestureDetector(
                      onLongPress: removingThis
                          ? null
                          : () =>
                              _showLeagueLongPressMenu(
                                  context, league),
                      child: LeagueFlipCard(
                        league: league,
                        leagueId: league.id,
                        leagueName: league.name,
                        leagueCode: league.code
                                .isNotEmpty
                            ? league.code
                            : (league.id.length >= 8
                                ? league.id
                                    .substring(0, 8)
                                : league.id),
                        distribution:
                            '${l10n.tr(league.format.l10nKey)} '
                            '• ${league.season}',
                        subtitle: subtitle,
                        imageUrl:
                            league.leagueImageUrl,
                        showMasterBadge: _selectedTab !=
                            _LeagueViewTab.master,
                        isLocked: false,
                        onPay: null,
                        isOwner: isOwner,
                        isViewer: viewerIsViewerOnly,
                        isFull: isFull,
                        onDoubleTap: (_rewardGateInProgress ||
                                removingThis)
                            ? null
                            : () =>
                                _handleLeagueCardDoubleTap(
                                    league),
                        qrWidget: QrImageView(
                          data: league.qrPayload,
                          version: QrVersions.auto,
                          gapless: true,
                          eyeStyle: const QrEyeStyle(
                            eyeShape: QrEyeShape.square,
                            color: Colors.black,
                          ),
                          dataModuleStyle:
                              const QrDataModuleStyle(
                            dataModuleShape:
                                QrDataModuleShape.square,
                            color: Colors.black,
                          ),
                        ),
                      ),
                    ),
                    if (isFull)
                      PositionedDirectional(
                        top: 12,
                        start: 12,
                        child: _CardBadge(
                          label: l10n
                              .tr('leagues_badge_full'),
                          icon: Icons.block_rounded,
                          color: Theme.of(context)
                              .colorScheme
                              .error,
                          bg: Theme.of(context)
                              .colorScheme
                              .error
                              .withOpacity(0.14),
                          border: Theme.of(context)
                              .colorScheme
                              .error
                              .withOpacity(0.40),
                        ),
                      ),
                    PositionedDirectional(
                      top: 12,
                      end: 12,
                      child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment.end,
                        children: [
                          if (_selectedTab ==
                              _LeagueViewTab.master)
                            Padding(
                              padding:
                                  const EdgeInsets.only(
                                      bottom: 6),
                              child: _CardBadge(
                                label: 'MASTER',
                                icon: Icons.hub_rounded,
                                color: _premiumAmber,
                                bg: _premiumAmber
                                    .withOpacity(0.14),
                                border: _premiumAmber
                                    .withOpacity(0.40),
                              ),
                            ),
                          Padding(
                            padding: const EdgeInsets.only(
                                bottom: 6),
                            child: _CardBadge(
                              label: league
                                  .footballCategory.badgeLabel,
                              icon: league
                                  .footballCategory.icon,
                              color: AppTheme.limeAccentDark,
                              bg: AppTheme.limeAccentDark
                                  .withOpacity(0.12),
                              border: AppTheme.limeAccentDark
                                  .withOpacity(0.35),
                            ),
                          ),
                          if (isOwner)
                            _CardBadge(
                              label: l10n.tr(
                                  'leagues_badge_owner'),
                              icon: Icons
                                  .admin_panel_settings_rounded,
                              color:
                                  const Color(0xFFEF4444),
                              bg: const Color(0xFFEF4444)
                                  .withOpacity(0.14),
                              border:
                                  const Color(0xFFEF4444)
                                      .withOpacity(0.40),
                            ),
                          if (!isOwner &&
                              viewerIsViewerOnly)
                            _CardBadge(
                              label: l10n.tr(
                                  'leagues_badge_viewer'),
                              icon: Icons
                                  .visibility_rounded,
                              color: AppTheme.secondaryText(
                                  brightness),
                              bg: AppTheme
                                  .searchBackground(
                                      brightness),
                              border:
                                  AppTheme.searchOutline(
                                      brightness),
                            ),
                        ],
                      ),
                    ),
                    if (!isOwner)
                      PositionedDirectional(
                        bottom: 14,
                        start: 14,
                        child: _CardBadge(
                          label: 'LONG PRESS',
                          icon: Icons.touch_app_rounded,
                          color: AppTheme.secondaryText(
                              brightness),
                          bg: AppTheme.searchBackground(
                              brightness),
                          border: AppTheme.searchOutline(
                              brightness),
                        ),
                      ),
                    if (_rewardGateInProgress)
                      Positioned.fill(
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius:
                                BorderRadius.circular(22),
                            color: Colors.black
                                .withOpacity(0.18),
                          ),
                          child: Column(
                            mainAxisAlignment:
                                MainAxisAlignment.center,
                            children: [
                              const SizedBox(
                                width: 26,
                                height: 26,
                                child:
                                    CircularProgressIndicator(
                                  strokeWidth: 2.4,
                                  color: AppTheme
                                      .limeAccentDark,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Container(
                                padding:
                                    const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  borderRadius:
                                      BorderRadius.circular(
                                          8),
                                  color: Colors.black
                                      .withOpacity(0.55),
                                ),
                                child: const Text(
                                  'Loading ad...',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight:
                                        FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    if (removingThis &&
                        !_rewardGateInProgress)
                      Positioned.fill(
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius:
                                BorderRadius.circular(22),
                            color: Colors.black
                                .withOpacity(0.12),
                          ),
                          child: const Center(
                            child: SizedBox(
                              width: 26,
                              height: 26,
                              child:
                                  CircularProgressIndicator(
                                strokeWidth: 2.4,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (showWorkspaceAction &&
                league.masterLeagueId
                    .trim()
                    .isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => context.push(
                        '/master-leagues/'
                        '${league.masterLeagueId}',
                      ),
                      icon:
                          const Icon(Icons.hub_rounded),
                      label: const Text(
                        'Open Workspace',
                        style: TextStyle(
                            fontWeight: FontWeight.w900),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    final media = MediaQuery.of(context);
    final bottomPadding = 16.0 +
        media.padding.bottom +
        kBottomNavigationBarHeight +
        80;

    final bool hasSearch = _searchQuery.trim().isNotEmpty;
    final bool isMasterTab =
        _selectedTab == _LeagueViewTab.master;
    final bool isAndroidBilling = PaymentPlatformConfig
        .routeAndroidPaymentsToGooglePlayBilling;

    return Center(
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: EdgeInsetsDirectional.fromSTEB(
          24,
          24,
          24,
          bottomPadding,
        ),
        child: Glass(
          borderRadius: 28,
          padding: const EdgeInsets.all(32),
          fill: AppTheme.cardColor(brightness),
          borderColor: AppTheme.cardBorder(brightness),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppTheme.iconCircleBackground(
                      brightness),
                ),
                child: Icon(
                  hasSearch
                      ? Icons.search_off_rounded
                      : (isMasterTab
                          ? Icons.hub_rounded
                          : Icons.emoji_events_rounded),
                  size: 36,
                  color: AppTheme.limeAccentDark,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                hasSearch
                    ? 'No leagues match your search'
                    : (isMasterTab
                        ? 'No master competitions yet'
                        : l10n.tr('leagues_empty_title')),
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                  fontSize: 20,
                  letterSpacing: -0.3,
                  color: AppTheme.primaryText(brightness),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              Text(
                hasSearch
                    ? 'Try another search term for league '
                      'name, code, region, or announcement.'
                    : (isMasterTab
                        ? 'Competitions you joined from a '
                          'master league container will '
                          'appear here.'
                        : l10n.tr('leagues_empty_subtitle')),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color:
                      AppTheme.secondaryText(brightness),
                  fontSize: 14,
                  height: 1.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: hasSearch
                        ? () => _searchController.clear()
                        : (_freeLimitReached
                            ? _openInlinePlanChooser
                            : () => _showOptions(context)),
                    borderRadius:
                        BorderRadius.circular(16),
                    child: Ink(
                      decoration: BoxDecoration(
                        borderRadius:
                            BorderRadius.circular(16),
                        color: hasSearch
                            ? AppTheme.limeAccent
                            : (_freeLimitReached
                                ? _premiumAmber
                                : AppTheme.limeAccent),
                      ),
                      child: Center(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              hasSearch
                                  ? Icons.restart_alt_rounded
                                  : (_freeLimitReached
                                      ? (isAndroidBilling
                                          ? Icons
                                              .shopping_bag_outlined
                                          : Icons
                                              .payments_rounded)
                                      : Icons.add_rounded),
                              color: AppTheme.darkText,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              hasSearch
                                  ? 'Clear Search'
                                  : (_freeLimitReached
                                      ? (isAndroidBilling
                                          ? 'Upgrade on Play'
                                          : 'Upgrade Plan')
                                      : l10n.tr(
                                          'leagues_empty_cta')),
                              style: const TextStyle(
                                color: AppTheme.darkText,
                                fontWeight: FontWeight.w800,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if (_freeLimitReached && !hasSearch) ...[
                const SizedBox(height: 12),
                Text(
                  _freeLimitMessage('create more'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: _premiumAmber,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    height: 1.35,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _showOptions(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    final media = MediaQuery.of(context);
    final bool isAndroidBilling = PaymentPlatformConfig
        .routeAndroidPaymentsToGooglePlayBilling;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        padding: const EdgeInsets.all(16),
        child: SafeArea(
          minimum: EdgeInsets.only(
            bottom: media.padding.bottom +
                kBottomNavigationBarHeight,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints:
                  const BoxConstraints(maxWidth: 500),
              child: Glass(
                borderRadius: 28,
                padding: const EdgeInsets.all(6),
                fill: AppTheme.cardColor(brightness),
                borderColor:
                    AppTheme.cardBorder(brightness),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(
                        top: 12,
                        bottom: 14,
                      ),
                      decoration: BoxDecoration(
                        color:
                            AppTheme.cardBorder(brightness),
                        borderRadius:
                            BorderRadius.circular(2),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14),
                      child: Column(
                        children: [
                          Text(
                            l10n.tr(
                                'leagues_options_title'),
                            style: theme
                                .textTheme.titleMedium
                                ?.copyWith(
                              fontWeight: FontWeight.w900,
                              fontSize: 18,
                              color: AppTheme.primaryText(
                                  brightness),
                            ),
                          ),
                          if (_freeLimitReached) ...[
                            const SizedBox(height: 8),
                            Text(
                              _freeLimitMessage(
                                'create more leagues or '
                                'competitions',
                              ),
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: _premiumAmber,
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                height: 1.35,
                              ),
                            ),
                          ] else ...[
                            const SizedBox(height: 8),
                            Text(
                              'Basic users can create up to '
                              '$_freeLeagueListLimit total '
                              'leagues or competitions. '
                              'Joining leagues remains '
                              'available.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color:
                                    AppTheme.secondaryText(
                                        brightness),
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                height: 1.35,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    _OptionTile(
                      icon: _freeLimitReached
                          ? (isAndroidBilling
                              ? Icons.shopping_bag_outlined
                              : Icons
                                  .workspace_premium_rounded)
                          : Icons.add_rounded,
                      iconBg: _freeLimitReached
                          ? _premiumAmber
                          : AppTheme.limeAccentDark,
                      title: _freeLimitReached
                          ? (isAndroidBilling
                              ? 'Upgrade on Google Play'
                              : 'Upgrade Plan')
                          : l10n.tr(
                              'leagues_options_create_title'),
                      subtitle: _freeLimitReached
                          ? (isAndroidBilling
                              ? 'Purchase a plan via Google '
                                'Play Billing to create more.'
                              : 'You used all free creation '
                                'slots. Upgrade to create more.')
                          : l10n.tr(
                              'leagues_options_create_subtitle'),
                      onTap: () async {
                        context.pop();
                        await _handleCreateLeagueTap(
                            context);
                      },
                    ),
                    Divider(
                      color: AppTheme.cardBorder(brightness),
                      height: 1,
                      indent: 16,
                      endIndent: 16,
                    ),
                    _OptionTile(
                      icon: Icons.qr_code_scanner_rounded,
                      iconBg: Colors.teal,
                      title: l10n.tr(
                          'leagues_options_join_qr_title'),
                      subtitle: l10n.tr(
                          'leagues_options_join_qr_subtitle'),
                      onTap: () async {
                        context.pop();
                        await _handleJoinQrTap(context);
                      },
                    ),
                    Divider(
                      color: AppTheme.cardBorder(brightness),
                      height: 1,
                      indent: 16,
                      endIndent: 16,
                    ),
                    _OptionTile(
                      icon: Icons.key_rounded,
                      iconBg: Colors.deepPurple,
                      title: l10n.tr(
                          'leagues_options_join_id_title'),
                      subtitle: l10n.tr(
                          'leagues_options_join_id_subtitle'),
                      onTap: () async {
                        context.pop();
                        await _handleJoinByIdTap(context);
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
  }

  Future<void> _showJoinByIdSheet(
      BuildContext context) async {
    final l10n = context.l10n;
    final brightness = Theme.of(context).brightness;

    final authUid = _authUidOrEmpty();
    if (authUid.isEmpty) {
      _snack('Please sign in and try again.');
      return;
    }

    if (_checkingPlan) {
      _snack('Checking your access. Please wait.');
      return;
    }

    final controller = TextEditingController();
    LeagueJoinMode mode = LeagueJoinMode.participant;
    String? error;
    bool joining = false;

    final repo = _repo;

    Future<void> doJoin(
        StateSetter setModalState) async {
      final code =
          controller.text.trim().toUpperCase();
      if (code.isEmpty) {
        setModalState(() =>
            error = l10n.tr('leagues_join_id_required'));
        return;
      }

      setModalState(() {
        joining = true;
        error = null;
      });

      try {
        if (kIsWeb) {
          final uid = authUid;

          final query = await _firestore
              .collection('leagues')
              .where('code', isEqualTo: code)
              .limit(1)
              .get(const GetOptions(source: Source.server))
              .timeout(const Duration(seconds: 20));

          if (query.docs.isEmpty) {
            setModalState(() {
              joining = false;
              error =
                  "No league found with that code. "
                  "Please check and try again.";
            });
            return;
          }

          final leagueDoc = query.docs.first;
          final leagueId = leagueDoc.id;

          await _firestore
              .collection('leagues')
              .doc(leagueId)
              .update({
            'memberIds': FieldValue.arrayUnion([uid]),
            'updatedAtMs':
                DateTime.now().millisecondsSinceEpoch,
          });

          if (mode == LeagueJoinMode.participant) {
            final membershipRef = _firestore
                .collection('leagues')
                .doc(leagueId)
                .collection('memberships')
                .doc(uid);

            final existing = await membershipRef
                .get(const GetOptions(source: Source.server))
                .timeout(const Duration(seconds: 10));

            if (!existing.exists) {
              await membershipRef.set({
                'id': uid,
                'leagueId': leagueId,
                'userId': uid,
                'teamId': null,
                'role': 1, // LeagueRole.member
                'updatedAtMs':
                    DateTime.now().millisecondsSinceEpoch,
                'version': 1,
              });
            }
          }

          if (!context.mounted) return;
          Navigator.of(context).pop();
          _snack(mode == LeagueJoinMode.viewer
              ? l10n.tr('leagues_join_snackbar_joined_viewer')
              : l10n.tr(
                  'leagues_join_snackbar_joined_participant'));
          if (mounted) {
            await _refreshLeagues();
          }
          return;
        }

        final league =
            await repo.joinLeagueLocallyByCode(
          joinCode: code,
          userId: authUid,
          mode: mode,
          placeholderBuilder: (generatedLeagueId) {
            final now =
                DateTime.now().millisecondsSinceEpoch;
            return League(
              id: generatedLeagueId,
              name: l10n.tr(
                  'leagues_joined_league_placeholder_name'),
              format: LeagueFormat.classic,
              privacy: LeaguePrivacy.private,
              region:
                  l10n.tr('common_region_global'),
              maxTeams: 20,
              season: '2026',
              organizerUid: '',
              organizerUserId: '',
              code: code,
              qrPayloadOverride: '',
              settings: LeagueSettings.defaultsFor(
                LeagueFormat.classic,
              ).copyWith(lastPulledAtMs: now),
              updatedAtMs: now,
              version: 1,
            );
          },
        );

        final Membership? membership =
            await repo.getMembership(
          leagueId: league.id,
          userId: authUid,
        );

        final effectiveMode = (membership != null)
            ? LeagueJoinMode.participant
            : LeagueJoinMode.viewer;

        if (!context.mounted) return;
        Navigator.of(context).pop();

        if (!context.mounted) return;

        String message;
        final bool adminAlreadyAdded =
            membership != null &&
                (membership.teamId?.trim().isNotEmpty ==
                    true);

        if (adminAlreadyAdded) {
          message = (mode == LeagueJoinMode.viewer)
              ? l10n.tr(
                  'leagues_join_snackbar_viewer_but_'
                  'already_added')
              : l10n.tr(
                  'leagues_join_snackbar_already_added');
        } else if (membership != null) {
          message = (mode == LeagueJoinMode.viewer)
              ? l10n.tr(
                  'leagues_join_snackbar_viewer_but_'
                  'already_registered',
                )
              : l10n.tr(
                  'leagues_join_snackbar_already_'
                  'registered');
        } else if (mode ==
                LeagueJoinMode.participant &&
            effectiveMode == LeagueJoinMode.viewer) {
          message = l10n.tr(
              'leagues_join_snackbar_league_full_'
              'joined_viewer');
        } else if (mode == LeagueJoinMode.viewer) {
          message = l10n
              .tr('leagues_join_snackbar_joined_viewer');
        } else {
          message = l10n.tr(
              'leagues_join_snackbar_joined_participant');
        }

        _snack(message);
        if (mounted) setState(() {});
      } catch (e) {
        setModalState(() {
          joining = false;
          error = UserFriendlyError.toMessage(
            e is Object ? e : Exception('unknown'),
          );
        });
      }
    }

    try {
      await showModalBottomSheet<void>(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        builder: (ctx) {
          final theme = Theme.of(ctx);
          final bottomInset =
              MediaQuery.of(ctx).viewInsets.bottom;

          return SafeArea(
            child: Padding(
              padding: EdgeInsets.only(
                      bottom: bottomInset)
                  .add(const EdgeInsets.all(12)),
              child: Center(
                child: ConstrainedBox(
                  constraints:
                      const BoxConstraints(maxWidth: 560),
                  child: Glass(
                    borderRadius: 28,
                    fill: AppTheme.cardColor(brightness),
                    borderColor:
                        AppTheme.cardBorder(brightness),
                    child: StatefulBuilder(
                      builder: (ctx, setModalState) {
                        return Padding(
                          padding:
                              const EdgeInsets.all(18),
                          child: Column(
                            mainAxisSize:
                                MainAxisSize.min,
                            children: [
                              Container(
                                width: 40,
                                height: 4,
                                margin:
                                    const EdgeInsets.only(
                                        bottom: 16),
                                decoration: BoxDecoration(
                                  color:
                                      AppTheme.cardBorder(
                                          brightness),
                                  borderRadius:
                                      BorderRadius.circular(
                                          2),
                                ),
                              ),
                              Container(
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color:
                                      AppTheme
                                          .iconCircleBackground(
                                              brightness),
                                ),
                                child: Icon(
                                  Icons.key_rounded,
                                  color: AppTheme
                                      .limeAccentDark,
                                  size: 24,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                l10n.tr(
                                    'leagues_join_sheet_title'),
                                style: theme.textTheme
                                    .titleMedium
                                    ?.copyWith(
                                  fontWeight:
                                      FontWeight.w900,
                                  fontSize: 18,
                                  color:
                                      AppTheme.primaryText(
                                          brightness),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                l10n.tr(
                                    'leagues_join_sheet_subtitle'),
                                style: TextStyle(
                                  color:
                                      AppTheme.secondaryText(
                                          brightness),
                                  fontSize: 12,
                                  fontWeight:
                                      FontWeight.w600,
                                ),
                                textAlign:
                                    TextAlign.center,
                              ),
                              const SizedBox(height: 16),
                              TextField(
                                controller: controller,
                                autofocus: true,
                                textCapitalization:
                                    TextCapitalization
                                        .characters,
                                style: TextStyle(
                                  fontWeight:
                                      FontWeight.w800,
                                  color:
                                      AppTheme.primaryText(
                                          brightness),
                                ),
                                decoration:
                                    InputDecoration(
                                  hintText: l10n.tr(
                                      'leagues_join_hint'),
                                  prefixIcon: const Icon(
                                      Icons.key_rounded),
                                  errorText: error,
                                ),
                                onChanged: (_) {
                                  if (error != null) {
                                    setModalState(
                                        () => error = null);
                                  }
                                },
                              ),
                              const SizedBox(height: 14),
                              Glass(
                                borderRadius: 18,
                                padding:
                                    const EdgeInsets.all(
                                        14),
                                fill:
                                    AppTheme.searchBackground(
                                        brightness),
                                borderColor:
                                    AppTheme.searchOutline(
                                        brightness),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment
                                          .start,
                                  children: [
                                    Text(
                                      l10n.tr(
                                          'leagues_join_as_title'),
                                      style: theme
                                          .textTheme
                                          .bodyMedium
                                          ?.copyWith(
                                        fontWeight:
                                            FontWeight.w900,
                                        color: AppTheme
                                            .primaryText(
                                                brightness),
                                      ),
                                    ),
                                    const SizedBox(
                                        height: 10),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: _ModeChip(
                                            label: l10n.tr(
                                              'leagues_join_participant',
                                            ),
                                            icon: Icons
                                                .sports_soccer_rounded,
                                            selected: mode ==
                                                LeagueJoinMode
                                                    .participant,
                                            onTap: joining
                                                ? null
                                                : () =>
                                                    setModalState(
                                                      () => mode =
                                                          LeagueJoinMode
                                                              .participant,
                                                    ),
                                          ),
                                        ),
                                        const SizedBox(
                                            width: 10),
                                        Expanded(
                                          child: _ModeChip(
                                            label: l10n.tr(
                                              'leagues_join_viewer_only',
                                            ),
                                            icon: Icons
                                                .visibility_rounded,
                                            selected: mode ==
                                                LeagueJoinMode
                                                    .viewer,
                                            onTap: joining
                                                ? null
                                                : () =>
                                                    setModalState(
                                                      () => mode =
                                                          LeagueJoinMode
                                                              .viewer,
                                                    ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(
                                        height: 8),
                                    Text(
                                      mode ==
                                              LeagueJoinMode
                                                  .viewer
                                          ? l10n.tr(
                                              'leagues_join_as_viewer_description',
                                            )
                                          : l10n.tr(
                                              'leagues_join_as_participant_description',
                                            ),
                                      style: TextStyle(
                                        color: AppTheme
                                            .secondaryText(
                                                brightness),
                                        fontSize: 11,
                                        height: 1.3,
                                        fontWeight:
                                            FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 16),
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton(
                                      onPressed: joining
                                          ? null
                                          : () =>
                                              Navigator.of(
                                                      ctx)
                                                  .pop(),
                                      child: Text(l10n.tr(
                                          'common_cancel')),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child:
                                        FilledButton.icon(
                                      style: FilledButton
                                          .styleFrom(
                                        backgroundColor:
                                            AppTheme
                                                .limeAccent,
                                        foregroundColor:
                                            AppTheme.darkText,
                                      ),
                                      onPressed: joining
                                          ? null
                                          : () => doJoin(
                                              setModalState),
                                      icon: joining
                                          ? const SizedBox(
                                              width: 18,
                                              height: 18,
                                              child:
                                                  CircularProgressIndicator(
                                                strokeWidth:
                                                    2,
                                                color: AppTheme
                                                    .darkText,
                                              ),
                                            )
                                          : const Icon(Icons
                                              .login_rounded),
                                      label: Text(l10n.tr(
                                          'common_join')),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      );
    } finally {
      controller.dispose();
    }
  }
}

class _TopLeagueSwitcher extends StatelessWidget {
  const _TopLeagueSwitcher({
    required this.selectedTab,
    required this.normalCount,
    required this.masterCount,
    required this.onChanged,
  });

  final _LeagueViewTab selectedTab;
  final int normalCount;
  final int masterCount;
  final ValueChanged<_LeagueViewTab> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;

    Widget chip({
      required _LeagueViewTab tab,
      required String label,
      required int count,
      required IconData icon,
    }) {
      final selected = selectedTab == tab;
      return Expanded(
        child: InkWell(
          onTap: () => onChanged(tab),
          borderRadius: BorderRadius.circular(999),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(
                horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              color: selected
                  ? AppTheme.limeAccent
                  : AppTheme.tabInactiveBackground(
                      brightness),
            ),
            child: Row(
              mainAxisAlignment:
                  MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 17,
                  color: selected
                      ? AppTheme.darkText
                      : AppTheme.tabInactiveText(
                          brightness),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    count > 0
                        ? '$label ($count)'
                        : label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelLarge
                        ?.copyWith(
                      color: selected
                          ? AppTheme.darkText
                          : AppTheme.tabInactiveText(
                              brightness),
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Glass(
      borderRadius: 999,
      padding: const EdgeInsets.all(6),
      fill: AppTheme.cardColor(brightness),
      borderColor: AppTheme.cardBorder(brightness),
      child: Row(
        children: [
          chip(
            tab: _LeagueViewTab.leagues,
            label: 'Leagues',
            count: normalCount,
            icon: Icons.emoji_events_outlined,
          ),
          const SizedBox(width: 6),
          chip(
            tab: _LeagueViewTab.master,
            label: 'Master',
            count: masterCount,
            icon: Icons.hub_rounded,
          ),
        ],
      ),
    );
  }
}

class _OptionTile extends StatelessWidget {
  const _OptionTile({
    required this.icon,
    required this.iconBg,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color iconBg;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: iconBg.withOpacity(0.15),
              ),
              child: Icon(icon, color: iconBg, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(
                          fontWeight: FontWeight.w900,
                          color: AppTheme.primaryText(
                              brightness),
                        ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: AppTheme.secondaryText(
                          brightness),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color:
                  AppTheme.secondaryText(brightness),
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}

class _ModeChip extends StatelessWidget {
  const _ModeChip({
    required this.label,
    required this.icon,
    required this.selected,
    this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final color = selected
        ? AppTheme.darkText
        : AppTheme.tabInactiveText(brightness);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding:
            const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: selected
              ? AppTheme.limeAccent
              : AppTheme.tabInactiveBackground(brightness),
          border: Border.all(
            color: selected
                ? AppTheme.limeAccentDark
                : AppTheme.cardBorder(brightness),
          ),
        ),
        child: Column(
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          color: selected
              ? AppTheme.limeAccent
              : AppTheme.tabInactiveBackground(brightness),
          border: Border.all(
            color: selected
                ? AppTheme.limeAccentDark
                : AppTheme.cardBorder(brightness),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected
                ? AppTheme.darkText
                : AppTheme.tabInactiveText(brightness),
            fontWeight: FontWeight.w900,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}

class _CardBadge extends StatelessWidget {
  const _CardBadge({
    required this.label,
    required this.icon,
    required this.color,
    required this.bg,
    required this.border,
  });

  final String label;
  final IconData icon;
  final Color color;
  final Color bg;
  final Color border;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 8,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 9,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }
}

bool auth_routerRefreshNeedsOnboardingFix(Object _) =>
    false;
