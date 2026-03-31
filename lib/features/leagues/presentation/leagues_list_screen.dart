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
import '../../../widgets/glass_search_bar.dart';
import '../../../widgets/league_flip_card.dart';
import '../data/leagues_repository_local.dart';
import '../models/league_announcement.dart';
import '../models/league_format.dart';

class LeaguesListScreen extends ConsumerStatefulWidget {
  const LeaguesListScreen({super.key});
  @override
  ConsumerState<LeaguesListScreen> createState() => _LeaguesListScreenState();
}

class _LeaguesListScreenState extends ConsumerState<LeaguesListScreen>
    with AutomaticKeepAliveClientMixin {
  static const Color _premiumAmber = Color(0xFFF59E0B);
  static const int _freeLeagueListLimit = 3;

  late LocalLeaguesRepository _repo;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  List<League> _leagues = [];
  Map<String, int> _participantCounts = {};
  Map<String, LeagueAnnouncement?> _latestAnnouncements = {};
  Map<String, bool> _viewerChargesPaid = {};
  Map<String, bool> _viewerIsParticipantByLeagueId = {};
  String _effectiveUserId = '';
  bool _isLoading = true;
  bool _loadingAnnouncements = false;
  String? _payingLeagueId;
  bool _isPremiumUser = false;
  String? _removingLeagueId;

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
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
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

  Future<void> _showLeagueLongPressMenu(BuildContext context, League league) async {
    final authUid = _authUidOrEmpty();
    final isOwner = _isOwnerForViewer(league, authUid);
    final canLeave = !isOwner;

    if (!canLeave) {
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
                        'You can remove this league from your list if you no longer need it.',
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
    final authUid = _authUidOrEmpty();
    if (authUid.isEmpty) {
      _snack('Please sign in and try again.');
      return;
    }

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

    if (mounted) setState(() => _removingLeagueId = league.id);

    try {
      await _firestore.collection('leagues').doc(league.id).set(
        {
          'memberIds': FieldValue.arrayRemove([authUid]),
          'updatedAtMs': DateTime.now().millisecondsSinceEpoch,
        },
        SetOptions(merge: true),
      ).timeout(const Duration(seconds: 15));

      try {
        await _firestore
            .collection('leagues')
            .doc(league.id)
            .collection('memberships')
            .doc(authUid)
            .delete()
            .timeout(const Duration(seconds: 15));
      } catch (_) {}

      if (!mounted) return;
      _snack('League removed from your list.');
      await _refreshLeagues();
    } catch (e) {
      if (!mounted) return;
      _snack(UserFriendlyError.toMessage(e is Object ? e : Exception('unknown')));
    } finally {
      if (mounted) setState(() => _removingLeagueId = null);
    }
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
      if (uid.isNotEmpty) count++;
    }
    return count;
  }

  @override
  void initState() {
    super.initState();
    _repo = LocalLeaguesRepository(ref.read(prefsServiceProvider));
    _loadLeagues(showSpinner: true);
  }

  Future<void> _loadLeagues({required bool showSpinner}) async {
    if (showSpinner) {
      if (!mounted) return;
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

          final requiresPaidLeague = league.format == LeagueFormat.uclGroup ||
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
          final data = snap.docs.first.data();
          latestAnns[league.id] = LeagueAnnouncement.fromMap(data);
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
    final paidAtMs = (data['paidAtMs'] is num) ? (data['paidAtMs'] as num).toInt() : 0;

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
    final paidAtMs = (data['paidAtMs'] is num) ? (data['paidAtMs'] as num).toInt() : 0;

    if (status == 'paid') return true;
    if (status.isEmpty && paidAtMs > 0) return true;

    return false;
  }

  Future<void> _storePaidChargesRemote({
    required String userId,
    required String leagueId,
    required Map<String, dynamic> payload,
  }) async {
    final uid = userId.trim();
    if (uid.isEmpty) return;
    await _firestore
        .collection('users')
        .doc(uid)
        .collection('leagueCharges')
        .doc(leagueId)
        .set(
          {
            'paid': true,
            'leagueId': leagueId,
            'userId': uid,
            'updatedAtMs': DateTime.now().millisecondsSinceEpoch,
            ...payload,
          },
          SetOptions(merge: true),
        )
        .timeout(const Duration(seconds: 15));
  }

  Future<void> _payChargesForLeague(BuildContext context, League league) async {
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
    final viewerIsParticipant = _viewerIsParticipantByLeagueId[league.id] ?? false;

    final requiresPaidLeague =
        league.format == LeagueFormat.uclGroup || league.format == LeagueFormat.uclSwiss;
    final isClassic = league.format == LeagueFormat.classic;

    final classicFullViewerRequiresUnlock = isClassic && isFull && !isOwner && !viewerIsParticipant;

    if (!requiresPaidLeague && !classicFullViewerRequiresUnlock) return;

    if (isOwner) {
      _snack(l10n.tr('leagues_creator_unlocked'));
      return;
    }

    final alreadyPaid = await _hasPaidChargesRemote(userId: authUid, leagueId: league.id);
    final alreadyCoupon = alreadyPaid ? false : await _hasPaidCouponRemote(userId: authUid, leagueId: league.id);

    if (alreadyPaid || alreadyCoupon) {
      if (!mounted) return;
      setState(() => _viewerChargesPaid[league.id] = true);
      return;
    }

    final couponCtrl = TextEditingController();
    bool busy = false;
    String? error;

    String _normalizeCoupon(String raw) {
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

      final code = _normalizeCoupon(couponCtrl.text);
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
                                icon: const Icon(Icons.payments_outlined),
                                label: busy
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      )
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
                                  border: Border.all(color: cs.error.withOpacity(0.25)),
                                ),
                                child: Text(
                                  error!.trim(),
                                  style: TextStyle(color: cs.error, fontWeight: FontWeight.w800),
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
    _refreshLeagues();
  }

  Future<void> _handleJoinQrTap(BuildContext context) async {
    if (_freeLimitReached) {
      await _openPremiumUpgradeFlow();
      return;
    }

    await context.push('/leagues/join-scanner');
    if (mounted) {
      _refreshLeagues();
    }
  }

  Future<void> _handleJoinByIdTap(BuildContext context) async {
    if (_freeLimitReached) {
      await _openPremiumUpgradeFlow();
      return;
    }

    await _showJoinByIdSheet(context);
    if (mounted) {
      _refreshLeagues();
    }
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
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
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
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
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
            Icon(Icons.chevron_right_rounded, color: onSurface.withOpacity(0.25), size: 20),
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
          color: selected ? cs.primary.withOpacity(0.12) : onSurface.withOpacity(0.04),
          border: Border.all(
            color: selected ? cs.primary.withOpacity(0.30) : onSurface.withOpacity(0.10),
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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
