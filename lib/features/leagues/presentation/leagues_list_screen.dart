import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:eleaguehub3/core/errors/user_friendly_error.dart';
import 'package:eleaguehub3/core/locale/app_localizations.dart';
import 'package:eleaguehub3/features/leagues/logic/coupon_codes_service.dart';
import 'package:eleaguehub3/features/leagues/logic/league_access_service.dart';
import 'package:eleaguehub3/features/leagues/logic/league_charges_payment_service.dart';
import 'package:eleaguehub3/features/leagues/logic/league_charges_store.dart';
import 'package:eleaguehub3/features/leagues/logic/league_creation_payment_service.dart';
import 'package:eleaguehub3/features/leagues/models/enums.dart';
import 'package:eleaguehub3/features/leagues/models/league.dart';
import 'package:eleaguehub3/features/leagues/models/league_announcement.dart';
import 'package:eleaguehub3/features/leagues/models/league_format.dart';
import 'package:eleaguehub3/features/leagues/models/league_settings.dart';
import 'package:eleaguehub3/features/leagues/models/membership.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/persistence/prefs_service.dart';
import '../../../core/widgets/glass.dart';
import '../../../core/widgets/glass_scaffold.dart';
import '../../../widgets/league_flip_card.dart';
import '../data/leagues_repository_local.dart';

enum _LeagueViewTab { leagues, master }

class LeaguesListScreen extends ConsumerStatefulWidget {
  const LeaguesListScreen({super.key});

  @override
  ConsumerState<LeaguesListScreen> createState() => _LeaguesListScreenState();
}

class _LeaguesListScreenState extends ConsumerState<LeaguesListScreen>
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
  bool _isPremiumUser = false;

  String? _payingLeagueId;
  String? _removingLeagueId;
  String _searchQuery = '';
  _LeagueViewTab _selectedTab = _LeagueViewTab.leagues;

  @override
  bool get wantKeepAlive => true;

  String _authUidOrEmpty() => FirebaseAuth.instance.currentUser?.uid.trim() ?? '';

  bool _looksLikeFirebaseUid(String s) => s.trim().length > 20;

  bool _isOwnerForViewer(League league, String viewerUid) {
    final v = viewerUid.trim();
    if (v.isEmpty) return false;

    final orgUid = league.organizerUid.trim();
    if (orgUid.isNotEmpty) return orgUid == v;

    final legacy = league.organizerUserId.trim();
    return legacy.isNotEmpty && legacy == v && _looksLikeFirebaseUid(legacy);
  }

  bool get _freeLimitReached =>
      !_isPremiumUser && _leagues.length >= _freeLeagueListLimit;

  String _freeLimitMessage([String action = 'add more leagues']) {
    return 'Free users can only have $_freeLeagueListLimit leagues total on the leagues screen. Upgrade to Premium to $action.';
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

  Future<bool> _detectPremiumUser(String uid) async {
    final trimmed = uid.trim();
    if (trimmed.isEmpty) return false;

    try {
      final token = await FirebaseAuth.instance.currentUser?.getIdTokenResult(true);
      final claims = token?.claims ?? const <String, dynamic>{};

      final isPremium = claims['isPremium'] == true || claims['premium'] == true;
      if (isPremium) return true;

      final premiumExpiresAtMs = claims['premiumExpiresAtMs'];
      if (premiumExpiresAtMs is int &&
          premiumExpiresAtMs > DateTime.now().millisecondsSinceEpoch) {
        return true;
      }
      if (premiumExpiresAtMs is num &&
          premiumExpiresAtMs.toInt() > DateTime.now().millisecondsSinceEpoch) {
        return true;
      }
    } catch (_) {}

    try {
      final userDoc = await _firestore
          .collection('users')
          .doc(trimmed)
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 10));

      final data = userDoc.data() ?? const <String, dynamic>{};
      if (data['isPremium'] == true) return true;

      final expires = data['premiumExpiresAtMs'];
      if (expires is int && expires > DateTime.now().millisecondsSinceEpoch) {
        return true;
      }
      if (expires is num &&
          expires.toInt() > DateTime.now().millisecondsSinceEpoch) {
        return true;
      }
    } catch (_) {}

    return false;
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

  Future<void> _openPremiumUpgradeFlow() async {
    if (_isPremiumUser) {
      _snack('Premium is already active on your account.');
      return;
    }

    final result = await context.push<LeagueCreationPaymentResult?>(
      '/leagues/create/payment',
      extra: <String, dynamic>{
        'premiumUpgrade': true,
        'leagueName': 'Organizer Premium',
      },
    );

    if (!mounted) return;

    if (result != null && result.success) {
      _snack('Premium upgrade payment completed. Refreshing access...');
      await _refreshLeagues();
      return;
    }

    if (result == null) {
      _snack('Premium upgrade cancelled.');
      return;
    }

    _snack(result.errorMessage ?? 'Premium upgrade failed.');
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

      final premium = await _detectPremiumUser(effectiveUserId);

      final leagues = await _repo.listLeagues().timeout(const Duration(seconds: 20));
      final memberships = await _repo.listMemberships().timeout(const Duration(seconds: 25));

      final Map<String, int> counts = {};
      final Map<String, bool> viewerIsParticipant = {};
      final Map<String, bool> viewerUnlocked = {};

      await Future.wait(
        leagues.map((league) async {
          final registered = await _countParticipantsRemote(league.id);
          counts[league.id] = registered;

          final isParticipant = memberships.any(
            (m) =>
                m.leagueId == league.id &&
                m.userId == effectiveUserId &&
                (m.role == LeagueRole.member || m.role == LeagueRole.organizer),
          );
          viewerIsParticipant[league.id] = isParticipant;

          final isOwner = _isOwnerForViewer(league, effectiveUserId);

          final requiresPaidLeague =
              league.format == LeagueFormat.uclGroup ||
                  league.format == LeagueFormat.uclSwiss;

          final isClassic = league.format == LeagueFormat.classic;
          final isFull = registered >= league.maxTeams;

          final classicFullViewerRequiresUnlock =
              isClassic && isFull && !isOwner && !isParticipant;

          if (isOwner) {
            viewerUnlocked[league.id] = true;
            return;
          }

          if (isClassic && isParticipant) {
            viewerUnlocked[league.id] = true;
            return;
          }

          if (!requiresPaidLeague && !classicFullViewerRequiresUnlock) {
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

          viewerUnlocked[league.id] = paidReceipt || paidCoupon;
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
        _isLoading = false;
      });

      unawaited(_loadLatestAnnouncements(leagues));
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _snack(UserFriendlyError.toMessage(e is Object ? e : Exception('unknown')));
    }
  }

  Future<void> _loadLatestAnnouncements(List<League> leagues) async {
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
              LeagueAnnouncement.fromMap(snap.docs.first.data());
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

  DocumentReference<Map<String, dynamic>> _leagueRef(String leagueId) =>
      _firestore.collection('leagues').doc(leagueId);

  CollectionReference<Map<String, dynamic>> _membershipsCol(String leagueId) =>
      _leagueRef(leagueId).collection('memberships');

  Future<int> _countParticipantsRemote(String leagueId) async {
    final snap = await _membershipsCol(leagueId)
        .get(const GetOptions(source: Source.server))
        .timeout(const Duration(seconds: 12));

    var count = 0;
    for (final d in snap.docs) {
      final data = d.data();
      final uid = (data['userId'] as String?)?.trim() ?? '';
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
    final receiptId = (data['receiptId'] ?? '').toString().trim();
    final paidAtMs =
        (data['paidAtMs'] is num) ? (data['paidAtMs'] as num).toInt() : 0;

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
    final status = (data['status'] ?? '').toString().trim().toLowerCase();
    final paidAtMs =
        (data['paidAtMs'] is num) ? (data['paidAtMs'] as num).toInt() : 0;

    if (status == 'paid') return true;
    if (status.isEmpty && paidAtMs > 0) return true;

    return false;
  }

  Future<void> _showLeagueLongPressMenu(
    BuildContext context,
    League league,
  ) async {
    final authUid = _authUidOrEmpty();
    final isOwner = _isOwnerForViewer(league, authUid);

    if (isOwner) {
      _snack('League owners should manage their league from the owner/admin area.');
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        final theme = Theme.of(sheetCtx);
        final cs = theme.colorScheme;

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 540),
                child: Glass(
                  borderRadius: 26,
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 40,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 14),
                        decoration: BoxDecoration(
                          color: cs.onSurface.withOpacity(0.20),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      Text(
                        league.name,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                          color: cs.onSurface,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        league.isInsideMasterLeague
                            ? 'This competition belongs to a master league workspace. You can still remove it from your personal list.'
                            : 'You can remove this league from your list if you no longer need it.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.onSurface.withOpacity(0.68),
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
                          icon: const Icon(Icons.exit_to_app_rounded),
                          label: const Text(
                            'Remove from My List',
                            style: TextStyle(fontWeight: FontWeight.w900),
                          ),
                        ),
                      ),
                      if (league.isInsideMasterLeague &&
                          league.masterLeagueId.trim().isNotEmpty) ...[
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.tonalIcon(
                            onPressed: () {
                              Navigator.of(sheetCtx).pop();
                              context.push('/master-leagues/${league.masterLeagueId}');
                            },
                            icon: const Icon(Icons.hub_rounded),
                            label: const Text(
                              'Open Workspace',
                              style: TextStyle(fontWeight: FontWeight.w900),
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: TextButton(
                          onPressed: () => Navigator.of(sheetCtx).pop(),
                          child: const Text(
                            'Cancel',
                            style: TextStyle(fontWeight: FontWeight.w900),
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
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) {
            final theme = Theme.of(ctx);
            final cs = theme.colorScheme;

            return Dialog(
              backgroundColor: Colors.transparent,
              child: Glass(
                borderRadius: 24,
                padding: const EdgeInsets.all(18),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.exit_to_app_rounded, color: cs.primary, size: 34),
                    const SizedBox(height: 10),
                    Text(
                      'Remove league from your list?',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'You will leave "${league.name}" and it will no longer appear on your leagues screen.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurface.withOpacity(0.70),
                        fontWeight: FontWeight.w700,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.of(ctx).pop(false),
                            child: const Text(
                              'Cancel',
                              style: TextStyle(fontWeight: FontWeight.w900),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton(
                            onPressed: () => Navigator.of(ctx).pop(true),
                            child: const Text(
                              'Remove',
                              style: TextStyle(fontWeight: FontWeight.w900),
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
      await _repo.leaveLeague(league.id);
      if (!mounted) return;
      _snack('League removed from your list.');
      await _refreshLeagues();
    } catch (e) {
      if (!mounted) return;
      _snack(UserFriendlyError.toMessage(e is Object ? e : Exception('unknown')));
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
    final cs = theme.colorScheme;
    final onSurface = cs.onSurface;

    if (_payingLeagueId == league.id) return;

    final authUid = _authUidOrEmpty();
    if (authUid.isEmpty) {
      _snack('Please sign in and try again.');
      return;
    }

    final registered = _participantCounts[league.id] ?? 0;
    final isFull = registered >= league.maxTeams;

    final isOwner = _isOwnerForViewer(league, authUid);
    final viewerIsParticipant =
        _viewerIsParticipantByLeagueId[league.id] ?? false;

    final requiresPaidLeague =
        league.format == LeagueFormat.uclGroup ||
            league.format == LeagueFormat.uclSwiss;
    final isClassic = league.format == LeagueFormat.classic;

    final classicFullViewerRequiresUnlock =
        isClassic && isFull && !isOwner && !viewerIsParticipant;

    if (!requiresPaidLeague && !classicFullViewerRequiresUnlock) return;

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
      setState(() => _viewerChargesPaid[league.id] = true);
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

    Future<void> unlockByPay(StateSetter setModalState) async {
      if (busy) return;

      setModalState(() {
        busy = true;
        error = null;
      });
      setState(() => _payingLeagueId = league.id);

      try {
        final paymentService = ref.read(leagueChargesPaymentServiceProvider);

        final result = await paymentService.payLeagueCharges(
          context: context,
          userId: authUid,
          leagueId: league.id,
          leagueName: league.name,
        );

        if (!mounted) return;

        if (!result.success) {
          setModalState(() {
            busy = false;
            error = result.errorMessage?.trim().isNotEmpty == true
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
            receiptId: result.receiptId ?? 'FLW-UNKNOWN',
            provider: result.provider,
            paidAtMs: result.paidAtMs,
          ),
        );

        await LeagueAccessService.instance.ensureDeterministicMembershipBestEffort(
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
          error = UserFriendlyError.toMessage(e is Object ? e : Exception('unknown'));
        });
        setState(() => _payingLeagueId = null);
      }
    }

    Future<void> unlockByCoupon(StateSetter setModalState) async {
      if (busy) return;

      final code = normalizeCoupon(couponCtrl.text);
      if (code.length < 6) {
        setModalState(() => error = 'Enter a valid coupon code.');
        return;
      }

      setModalState(() {
        busy = true;
        error = null;
      });
      setState(() => _payingLeagueId = league.id);

      try {
        final res = await CouponCodesService().redeemWithCode(
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
            error = res.errorMessage?.trim().isNotEmpty == true
                ? res.errorMessage
                : 'Coupon redemption failed.';
          });
          setState(() => _payingLeagueId = null);
          return;
        }

        await LeagueAccessService.instance.ensureDeterministicMembershipBestEffort(
          leagueId: league.id,
          uid: authUid,
        );
      } catch (_) {}

      try {
        await LeagueAccessService.instance.ensureDeterministicMembershipBestEffort(
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
        final bottomInset = MediaQuery.of(sheetCtx).viewInsets.bottom;

        return SafeArea(
          child: Padding(
            padding: EdgeInsets.only(bottom: bottomInset).add(const EdgeInsets.all(12)),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Glass(
                  borderRadius: 28,
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
                              margin: const EdgeInsets.only(bottom: 16),
                              decoration: BoxDecoration(
                                color: onSurface.withOpacity(0.25),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            Text(
                              'Unlock access',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w900,
                                fontSize: 18,
                                color: onSurface,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              league.name,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: onSurface.withOpacity(0.55),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            if (classicFullViewerRequiresUnlock) ...[
                              const SizedBox(height: 10),
                              Text(
                                'This classic league is full. You can unlock access as a viewer by paying or using a coupon.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: onSurface.withOpacity(0.50),
                                  fontSize: 12,
                                  height: 1.35,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                            const SizedBox(height: 16),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton.icon(
                                onPressed: busy ? null : () => unlockByPay(setModalState),
                                icon: busy
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      )
                                    : const Icon(Icons.payments_outlined),
                                label: busy
                                    ? const Text('')
                                    : const Text(
                                        'Pay to unlock',
                                        style: TextStyle(fontWeight: FontWeight.w900),
                                      ),
                              ),
                            ),
                            const SizedBox(height: 14),
                            Align(
                              alignment: AlignmentDirectional.centerStart,
                              child: Text(
                                'Or use a coupon',
                                style: TextStyle(
                                  color: onSurface.withOpacity(0.75),
                                  fontWeight: FontWeight.w900,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: couponCtrl,
                              enabled: !busy,
                              textCapitalization: TextCapitalization.characters,
                              decoration: const InputDecoration(
                                prefixIcon: Icon(Icons.confirmation_number_outlined),
                                hintText: 'Enter coupon code',
                              ),
                              onSubmitted: (_) => unlockByCoupon(setModalState),
                            ),
                            const SizedBox(height: 10),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: busy ? null : () => unlockByCoupon(setModalState),
                                icon: const Icon(Icons.verified_outlined),
                                label: const Text(
                                  'Apply coupon',
                                  style: TextStyle(fontWeight: FontWeight.w900),
                                ),
                              ),
                            ),
                            if ((error ?? '').trim().isNotEmpty) ...[
                              const SizedBox(height: 12),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: cs.error.withOpacity(0.10),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: cs.error.withOpacity(0.25),
                                  ),
                                ),
                                child: Text(
                                  error!.trim(),
                                  style: TextStyle(
                                    color: cs.error,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ],
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              child: TextButton(
                                onPressed: busy ? null : () => Navigator.of(ctx).pop(),
                                child: Text(l10n.tr('common_cancel')),
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

  Future<void> _handleCreateLeagueTap(BuildContext context) async {
    if (_freeLimitReached) {
      await _openPremiumUpgradeFlow();
      return;
    }

    await context.push('/leagues/create');
    if (mounted) {
      await _refreshLeagues();
    }
  }

  Future<void> _handleJoinQrTap(BuildContext context) async {
    if (_freeLimitReached) {
      await _openPremiumUpgradeFlow();
      return;
    }

    await context.push('/leagues/join-scanner');
    if (mounted) {
      await _refreshLeagues();
    }
  }

  Future<void> _handleJoinByIdTap(BuildContext context) async {
    if (_freeLimitReached) {
      await _openPremiumUpgradeFlow();
      return;
    }

    await _showJoinByIdSheet(context);
    if (mounted) {
      await _refreshLeagues();
    }
  }

  List<League> _filteredLeagues() {
    final q = _searchQuery.trim().toLowerCase();

    final base = _selectedTab == _LeagueViewTab.leagues
        ? _leagues.where((l) => !l.isInsideMasterLeague).toList()
        : _leagues.where((l) => l.isInsideMasterLeague).toList();

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
      '$registered / ${league.maxTeams} ${l10n.tr('leagues_teams_word')}',
    ];

    if (league.viewerCapacity > 0) {
      pieces.add('${league.viewerCapacity} Viewers');
    }

    final desc = league.description.trim();
    if (desc.isNotEmpty) {
      pieces.add(desc);
    }

    if (latestAnn != null && latestAnn.title.trim().isNotEmpty) {
      pieces.add(latestAnn.title.trim());
    }

    return pieces.join(' • ');
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final l10n = context.l10n;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final onSurface = cs.onSurface;

    final media = MediaQuery.of(context);
    final screenWidth = media.size.width;
    final isTablet = screenWidth >= 600;
    final fabBottomOffset =
        kBottomNavigationBarHeight + media.padding.bottom + 16;

    final filtered = _filteredLeagues();
    final normalCount = _leagues.where((l) => !l.isInsideMasterLeague).length;
    final masterCount = _leagues.where((l) => l.isInsideMasterLeague).length;

    return GlassScaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        title: const Text(''),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        actions: [
          IconButton(
            tooltip: l10n.tr('common_refresh'),
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _refreshLeagues,
          ),
        ],
      ),
      floatingActionButton: Padding(
        padding: EdgeInsets.only(bottom: fabBottomOffset),
        child: FloatingActionButton(
          onPressed: () => _showOptions(context),
          backgroundColor: _freeLimitReached ? _premiumAmber : cs.primary,
          foregroundColor: _freeLimitReached ? Colors.black : cs.onPrimary,
          child: Icon(
            _freeLimitReached
                ? Icons.workspace_premium_rounded
                : Icons.add_rounded,
          ),
        ),
      ),
      floatingActionButtonLocation:
          FloatingActionButtonLocation.endFloat,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: isTablet ? 900 : 600),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                  child: Glass(
                    borderRadius: 20,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 14,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 42,
                              height: 42,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    cs.primary.withOpacity(0.30),
                                    cs.primary.withOpacity(0.08),
                                  ],
                                ),
                              ),
                              child: Icon(
                                Icons.emoji_events_rounded,
                                color: cs.primary,
                                size: 22,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    l10n.tr('leagues_my_leagues_title'),
                                    style: theme.textTheme.titleMedium
                                        ?.copyWith(
                                      fontWeight: FontWeight.w900,
                                      fontSize: 18,
                                      letterSpacing: -0.3,
                                      color: onSurface,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    _isLoading
                                        ? 'Loading...'
                                        : '${_leagues.length} league${_leagues.length == 1 ? '' : 's'}',
                                    style: TextStyle(
                                      color: onSurface.withOpacity(0.55),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        if (!_isLoading) ...[
                          const SizedBox(height: 10),
                          Text(
                            _isPremiumUser
                                ? 'Premium active: you can have more than $_freeLeagueListLimit league cards.'
                                : (_freeLimitReached
                                    ? 'Free limit reached: you already have $_freeLeagueListLimit league cards. Upgrade to Premium to add more.'
                                    : 'Free plan: you can have up to $_freeLeagueListLimit league cards total.'),
                            style: TextStyle(
                              color: _isPremiumUser
                                  ? cs.primary
                                  : (_freeLimitReached
                                      ? _premiumAmber
                                      : onSurface.withOpacity(0.62)),
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              height: 1.35,
                            ),
                          ),
                          if (!_isPremiumUser) ...[
                            const SizedBox(height: 10),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton.icon(
                                onPressed: _openPremiumUpgradeFlow,
                                style: FilledButton.styleFrom(
                                  backgroundColor: _freeLimitReached
                                      ? _premiumAmber
                                      : cs.primary,
                                  foregroundColor: _freeLimitReached
                                      ? Colors.black
                                      : cs.onPrimary,
                                ),
                                icon: const Icon(Icons.payments_outlined),
                                label: Text(
                                  _freeLimitReached
                                      ? 'Pay Now'
                                      : 'Upgrade to Premium',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Glass(
                    borderRadius: 18,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.search_rounded, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: _searchController,
                            decoration: const InputDecoration(
                              hintText:
                                  'Search leagues, codes, announcements...',
                              border: InputBorder.none,
                              isDense: true,
                            ),
                          ),
                        ),
                        if (_searchQuery.trim().isNotEmpty)
                          IconButton(
                            tooltip: 'Clear',
                            onPressed: () {
                              _searchController.clear();
                            },
                            icon: const Icon(Icons.close_rounded),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
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
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: _isLoading
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                CircularProgressIndicator(
                                  color: cs.primary,
                                ),
                                const SizedBox(height: 14),
                                Text(
                                  'Loading leagues...',
                                  style: TextStyle(
                                    color: onSurface.withOpacity(0.55),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : filtered.isEmpty
                            ? _buildEmptyState(context)
                            : _buildLeagueGrid(context, filtered, isTablet),
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
    final cs = Theme.of(context).colorScheme;
    final onSurface = cs.onSurface;

    final viewerUid = _effectiveUserId.trim();
    final authUid = _authUidOrEmpty();

    final cardHeight = isTablet ? 250.0 : 250.0;
    final showWorkspaceAction = _selectedTab == _LeagueViewTab.master;
    final extraActionHeight = showWorkspaceAction ? 52.0 : 0.0;
    final mainAxisExtent = cardHeight + extraActionHeight;

    return GridView.builder(
      shrinkWrap: true,
      itemCount: leagues.length,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      padding: EdgeInsets.fromLTRB(
        16,
        8,
        16,
        16 + MediaQuery.of(context).padding.bottom + kBottomNavigationBarHeight + 80,
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
            _viewerIsParticipantByLeagueId[league.id] ?? false;
        final bool viewerIsViewerOnly = !isOwner && !viewerIsParticipant;

        final registered = _participantCounts[league.id] ?? 0;
        final isFull = registered >= league.maxTeams;

        final latestAnn = _latestAnnouncements[league.id];
        final subtitle = _buildCardSubtitle(
          context: context,
          league: league,
          registered: registered,
          latestAnn: latestAnn,
        );

        final removingThis = _removingLeagueId == league.id;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Opacity(
                opacity: removingThis ? 0.65 : 1,
                child: Stack(
                  children: [
                    GestureDetector(
                      onLongPress: removingThis
                          ? null
                          : () => _showLeagueLongPressMenu(context, league),
                      child: LeagueFlipCard(
                        league: league,
                        leagueId: league.id,
                        leagueName: league.name,
                        leagueCode: league.code.isNotEmpty
                            ? league.code
                            : (league.id.length >= 8
                                ? league.id.substring(0, 8)
                                : league.id),
                        distribution:
                            '${l10n.tr(league.format.l10nKey)} • ${league.season}',
                        subtitle: subtitle,
                        imageUrl: league.leagueImageUrl,
                        showMasterBadge: _selectedTab != _LeagueViewTab.master,
                        isLocked: false,
                        onPay: null,
                        isOwner: isOwner,
                        isViewer: viewerIsViewerOnly,
                        isFull: isFull,
                        onDoubleTap: () => context.push('/leagues/${league.id}'),
                        qrWidget: QrImageView(
                          data: league.qrPayload,
                          version: QrVersions.auto,
                          gapless: true,
                          eyeStyle: const QrEyeStyle(
                            eyeShape: QrEyeShape.square,
                            color: Colors.black,
                          ),
                          dataModuleStyle: const QrDataModuleStyle(
                            dataModuleShape: QrDataModuleShape.square,
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
                          label: l10n.tr('leagues_badge_full'),
                          icon: Icons.block_rounded,
                          color: cs.error,
                          bg: cs.error.withOpacity(0.14),
                          border: cs.error.withOpacity(0.40),
                        ),
                      ),
                    PositionedDirectional(
                      top: 12,
                      end: 12,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          if (_selectedTab == _LeagueViewTab.master)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: _CardBadge(
                                label: 'MASTER',
                                icon: Icons.hub_rounded,
                                color: _premiumAmber,
                                bg: _premiumAmber.withOpacity(0.14),
                                border: _premiumAmber.withOpacity(0.40),
                              ),
                            ),
                          if (isOwner)
                            _CardBadge(
                              label: l10n.tr('leagues_badge_owner'),
                              icon: Icons.admin_panel_settings_rounded,
                              color: cs.primary,
                              bg: cs.primary.withOpacity(0.18),
                              border: cs.primary.withOpacity(0.45),
                            ),
                          if (!isOwner && viewerIsViewerOnly)
                            _CardBadge(
                              label: l10n.tr('leagues_badge_viewer'),
                              icon: Icons.visibility_rounded,
                              color: onSurface.withOpacity(0.70),
                              bg: onSurface.withOpacity(0.06),
                              border: onSurface.withOpacity(0.12),
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
                          color: onSurface.withOpacity(0.78),
                          bg: onSurface.withOpacity(0.08),
                          border: onSurface.withOpacity(0.14),
                        ),
                      ),
                    if (removingThis)
                      Positioned.fill(
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(22),
                            color: Colors.black.withOpacity(0.12),
                          ),
                          child: const Center(
                            child: SizedBox(
                              width: 26,
                              height: 26,
                              child: CircularProgressIndicator(
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
                league.masterLeagueId.trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () =>
                          context.push('/master-leagues/${league.masterLeagueId}'),
                      icon: const Icon(Icons.hub_rounded),
                      label: const Text(
                        'Open Workspace',
                        style: TextStyle(fontWeight: FontWeight.w900),
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
    final cs = theme.colorScheme;
    final onSurface = cs.onSurface;
    final media = MediaQuery.of(context);
    final bottomPadding =
        16.0 + media.padding.bottom + kBottomNavigationBarHeight + 80;

    final bool hasSearch = _searchQuery.trim().isNotEmpty;
    final bool isMasterTab = _selectedTab == _LeagueViewTab.master;

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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      cs.primary.withOpacity(0.25),
                      cs.primary.withOpacity(0.08),
                    ],
                  ),
                ),
                child: Icon(
                  hasSearch
                      ? Icons.search_off_rounded
                      : (isMasterTab
                          ? Icons.hub_rounded
                          : Icons.emoji_events_rounded),
                  size: 36,
                  color: cs.primary,
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
                  color: onSurface,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              Text(
                hasSearch
                    ? 'Try another search term for league name, code, region, or announcement.'
                    : (isMasterTab
                        ? 'Competitions you joined from a master league container will appear here.'
                        : l10n.tr('leagues_empty_subtitle')),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: onSurface.withOpacity(0.60),
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
                            ? _openPremiumUpgradeFlow
                            : () => _showOptions(context)),
                    borderRadius: BorderRadius.circular(16),
                    child: Ink(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        gradient: LinearGradient(
                          colors: hasSearch
                              ? [cs.primary, cs.primary.withOpacity(0.75)]
                              : (_freeLimitReached
                                  ? [
                                      _premiumAmber,
                                      _premiumAmber.withOpacity(0.82),
                                    ]
                                  : [
                                      cs.primary,
                                      cs.primary.withOpacity(0.75),
                                    ]),
                        ),
                      ),
                      child: Center(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              hasSearch
                                  ? Icons.restart_alt_rounded
                                  : (_freeLimitReached
                                      ? Icons.payments_rounded
                                      : Icons.add_rounded),
                              color: hasSearch
                                  ? Colors.white
                                  : (_freeLimitReached
                                      ? Colors.black
                                      : Colors.white),
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              hasSearch
                                  ? 'Clear Search'
                                  : (_freeLimitReached
                                      ? 'Pay Now'
                                      : l10n.tr('leagues_empty_cta')),
                              style: TextStyle(
                                color: hasSearch
                                    ? Colors.white
                                    : (_freeLimitReached
                                        ? Colors.black
                                        : Colors.white),
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
                  _freeLimitMessage('add more'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
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
    final cs = theme.colorScheme;
    final onSurface = cs.onSurface;
    final media = MediaQuery.of(context);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        padding: const EdgeInsets.all(16),
        child: SafeArea(
          minimum: EdgeInsets.only(
            bottom: media.padding.bottom + kBottomNavigationBarHeight,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 500),
              child: Glass(
                borderRadius: 28,
                padding: const EdgeInsets.all(6),
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
                        color: onSurface.withOpacity(0.20),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: Column(
                        children: [
                          Text(
                            l10n.tr('leagues_options_title'),
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w900,
                              fontSize: 18,
                              color: onSurface,
                            ),
                          ),
                          if (_freeLimitReached) ...[
                            const SizedBox(height: 8),
                            Text(
                              _freeLimitMessage('add more leagues'),
                              textAlign: TextAlign.center,
                              style: TextStyle(
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
                    const SizedBox(height: 14),
                    _OptionTile(
                      icon: _freeLimitReached
                          ? Icons.workspace_premium_rounded
                          : Icons.add_rounded,
                      iconBg:
                          _freeLimitReached ? _premiumAmber : cs.primary,
                      title: _freeLimitReached
                          ? 'Pay Now'
                          : l10n.tr('leagues_options_create_title'),
                      subtitle: _freeLimitReached
                          ? 'Upgrade to Premium to create more leagues.'
                          : l10n.tr('leagues_options_create_subtitle'),
                      onTap: () async {
                        context.pop();
                        await _handleCreateLeagueTap(context);
                      },
                    ),
                    Divider(
                      color: onSurface.withOpacity(0.08),
                      height: 1,
                      indent: 16,
                      endIndent: 16,
                    ),
                    _OptionTile(
                      icon: _freeLimitReached
                          ? Icons.workspace_premium_rounded
                          : Icons.qr_code_scanner_rounded,
                      iconBg:
                          _freeLimitReached ? _premiumAmber : Colors.teal,
                      title: _freeLimitReached
                          ? 'Pay Now'
                          : l10n.tr('leagues_options_join_qr_title'),
                      subtitle: _freeLimitReached
                          ? 'Upgrade to Premium to join more leagues.'
                          : l10n.tr('leagues_options_join_qr_subtitle'),
                      onTap: () async {
                        context.pop();
                        await _handleJoinQrTap(context);
                      },
                    ),
                    Divider(
                      color: onSurface.withOpacity(0.08),
                      height: 1,
                      indent: 16,
                      endIndent: 16,
                    ),
                    _OptionTile(
                      icon: _freeLimitReached
                          ? Icons.workspace_premium_rounded
                          : Icons.key_rounded,
                      iconBg: _freeLimitReached
                          ? _premiumAmber
                          : Colors.deepPurple,
                      title: _freeLimitReached
                          ? 'Pay Now'
                          : l10n.tr('leagues_options_join_id_title'),
                      subtitle: _freeLimitReached
                          ? 'Upgrade to Premium to join more leagues.'
                          : l10n.tr('leagues_options_join_id_subtitle'),
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

  Future<void> _showJoinByIdSheet(BuildContext context) async {
    final l10n = context.l10n;

    final authUid = _authUidOrEmpty();
    if (authUid.isEmpty) {
      _snack('Please sign in and try again.');
      return;
    }

    if (_freeLimitReached) {
      await _openPremiumUpgradeFlow();
      return;
    }

    final controller = TextEditingController();
    LeagueJoinMode mode = LeagueJoinMode.participant;
    String? error;
    bool joining = false;

    final repo = _repo;

    Future<void> doJoin(StateSetter setModalState) async {
      final code = controller.text.trim().toUpperCase();
      if (code.isEmpty) {
        setModalState(() => error = l10n.tr('leagues_join_id_required'));
        return;
      }

      setModalState(() {
        joining = true;
        error = null;
      });

      try {
        final league = await repo.joinLeagueLocallyByCode(
          joinCode: code,
          userId: authUid,
          mode: mode,
          placeholderBuilder: (generatedLeagueId) {
            final now = DateTime.now().millisecondsSinceEpoch;
            return League(
              id: generatedLeagueId,
              name: l10n.tr('leagues_joined_league_placeholder_name'),
              format: LeagueFormat.classic,
              privacy: LeaguePrivacy.private,
              region: l10n.tr('common_region_global'),
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

        final Membership? membership = await repo.getMembership(
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
                (membership.teamId?.trim().isNotEmpty == true);

        if (adminAlreadyAdded) {
          message = (mode == LeagueJoinMode.viewer)
              ? l10n.tr('leagues_join_snackbar_viewer_but_already_added')
              : l10n.tr('leagues_join_snackbar_already_added');
        } else if (membership != null) {
          message = (mode == LeagueJoinMode.viewer)
              ? l10n.tr(
                  'leagues_join_snackbar_viewer_but_already_registered',
                )
              : l10n.tr('leagues_join_snackbar_already_registered');
        } else if (mode == LeagueJoinMode.participant &&
            effectiveMode == LeagueJoinMode.viewer) {
          message =
              l10n.tr('leagues_join_snackbar_league_full_joined_viewer');
        } else if (mode == LeagueJoinMode.viewer) {
          message = l10n.tr('leagues_join_snackbar_joined_viewer');
        } else {
          message =
              l10n.tr('leagues_join_snackbar_joined_participant');
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
          final cs = theme.colorScheme;
          final onSurface = cs.onSurface;
          final bottomInset = MediaQuery.of(ctx).viewInsets.bottom;

          return SafeArea(
            child: Padding(
              padding: EdgeInsets.only(bottom: bottomInset)
                  .add(const EdgeInsets.all(12)),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Glass(
                    borderRadius: 28,
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
                                margin: const EdgeInsets.only(bottom: 16),
                                decoration: BoxDecoration(
                                  color: onSurface.withOpacity(0.20),
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                              Container(
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [
                                      cs.primary.withOpacity(0.30),
                                      cs.primary.withOpacity(0.08),
                                    ],
                                  ),
                                ),
                                child: Icon(
                                  Icons.key_rounded,
                                  color: cs.primary,
                                  size: 24,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                l10n.tr('leagues_join_sheet_title'),
                                style: theme.textTheme.titleMedium
                                    ?.copyWith(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 18,
                                  color: onSurface,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                l10n.tr('leagues_join_sheet_subtitle'),
                                style: TextStyle(
                                  color: onSurface.withOpacity(0.55),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 16),
                              TextField(
                                controller: controller,
                                autofocus: true,
                                textCapitalization:
                                    TextCapitalization.characters,
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: onSurface,
                                ),
                                decoration: InputDecoration(
                                  hintText: l10n.tr('leagues_join_hint'),
                                  prefixIcon: const Icon(Icons.key_rounded),
                                  errorText: error,
                                ),
                                onChanged: (_) {
                                  if (error != null) {
                                    setModalState(() => error = null);
                                  }
                                },
                              ),
                              const SizedBox(height: 14),
                              Glass(
                                borderRadius: 18,
                                padding: const EdgeInsets.all(14),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      l10n.tr('leagues_join_as_title'),
                                      style: theme.textTheme.bodyMedium
                                          ?.copyWith(
                                        fontWeight: FontWeight.w900,
                                        color: onSurface,
                                      ),
                                    ),
                                    const SizedBox(height: 10),
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
                                                LeagueJoinMode.participant,
                                            onTap: joining
                                                ? null
                                                : () => setModalState(
                                                      () => mode =
                                                          LeagueJoinMode
                                                              .participant,
                                                    ),
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: _ModeChip(
                                            label: l10n.tr(
                                              'leagues_join_viewer_only',
                                            ),
                                            icon:
                                                Icons.visibility_rounded,
                                            selected: mode ==
                                                LeagueJoinMode.viewer,
                                            onTap: joining
                                                ? null
                                                : () => setModalState(
                                                      () => mode =
                                                          LeagueJoinMode
                                                              .viewer,
                                                    ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      mode == LeagueJoinMode.viewer
                                          ? l10n.tr(
                                              'leagues_join_as_viewer_description',
                                            )
                                          : l10n.tr(
                                              'leagues_join_as_participant_description',
                                            ),
                                      style: TextStyle(
                                        color: onSurface.withOpacity(0.55),
                                        fontSize: 11,
                                        height: 1.3,
                                        fontWeight: FontWeight.w600,
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
                                          : () => Navigator.of(ctx).pop(),
                                      child:
                                          Text(l10n.tr('common_cancel')),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: FilledButton.icon(
                                      onPressed: joining
                                          ? null
                                          : () => doJoin(setModalState),
                                      icon: joining
                                          ? const SizedBox(
                                              width: 18,
                                              height: 18,
                                              child:
                                                  CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: Colors.white,
                                              ),
                                            )
                                          : const Icon(
                                              Icons.login_rounded,
                                            ),
                                      label: Text(l10n.tr('common_join')),
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
    final cs = theme.colorScheme;
    final onSurface = cs.onSurface;

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
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              color: selected
                  ? cs.primary
                  : Colors.transparent,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 17,
                  color: selected ? cs.onPrimary : onSurface.withOpacity(0.70),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    count > 0 ? '$label ($count)' : label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: selected ? cs.onPrimary : onSurface.withOpacity(0.78),
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
    final onSurface = Theme.of(context).colorScheme.onSurface;

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
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleSmall
                        ?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: onSurface.withOpacity(0.55),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: onSurface.withOpacity(0.25),
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
    final cs = Theme.of(context).colorScheme;
    final onSurface = cs.onSurface;
    final color = selected ? cs.primary : onSurface.withOpacity(0.60);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: selected
              ? cs.primary.withOpacity(0.12)
              : onSurface.withOpacity(0.04),
          border: Border.all(
            color: selected
                ? cs.primary.withOpacity(0.30)
                : onSurface.withOpacity(0.10),
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

bool auth_routerRefreshNeedsOnboardingFix(Object _) => false;
