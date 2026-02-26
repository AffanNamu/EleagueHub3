import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:eleaguehub3/core/errors/user_friendly_error.dart';
import 'package:eleaguehub3/core/locale/app_localizations.dart';
import 'package:eleaguehub3/features/leagues/logic/league_charges_payment_service.dart';
import 'package:eleaguehub3/features/leagues/logic/league_charges_store.dart';
import 'package:eleaguehub3/features/leagues/logic/league_access_service.dart';
import 'package:eleaguehub3/features/leagues/logic/coupon_codes_service.dart';
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

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
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
    // ignore: discarded_futures
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
              league.format == LeagueFormat.uclGroup || league.format == LeagueFormat.uclSwiss;

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
    final alreadyCoupon =
        alreadyPaid ? false : await _hasPaidCouponRemote(userId: authUid, leagueId: league.id);

    if (alreadyPaid || alreadyCoupon) {
      if (!mounted) return;
      setState(() => _viewerChargesPaid[league.id] = true);
      return;
    }

    final couponCtrl = TextEditingController();
    bool busy = false;
    String? error;

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

    String _normalizeCoupon(String raw) {
      return raw
          .trim()
          .toUpperCase()
          .replaceAll(' ', '')
          .replaceAll('-', '')
          .replaceAll(RegExp(r'[^A-Z0-9_%]'), '');
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
            error =
                res.errorMessage?.trim().isNotEmpty == true ? res.errorMessage : 'Coupon redemption failed.';
          });
          setState(() => _payingLeagueId = null);
          return;
        }

        await LeagueAccessService.instance.ensureDeterministicMembershipBestEffort(
          leagueId: league.id,
          uid: authUid,
        );
      } catch (e) {}

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
        final theme = Theme.of(sheetCtx);
        final cs = theme.colorScheme;
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
                                color: Colors.white.withOpacity(0.25),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            Text(
                              'Unlock access',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w900,
                                fontSize: 18,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              league.name,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.55),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            if (classicFullViewerRequiresUnlock) ...[
                              const SizedBox(height: 10),
                              Text(
                                'This classic league is full. You can unlock access as a viewer by paying or using a coupon.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.50),
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
                                    : const Text('Pay to unlock', style: TextStyle(fontWeight: FontWeight.w900)),
                              ),
                            ),
                            const SizedBox(height: 14),
                            Align(
                              alignment: AlignmentDirectional.centerStart,
                              child: Text(
                                'Or use a coupon',
                                style: TextStyle(
                                  color: cs.onSurface.withOpacity(0.75),
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
                                label: const Text('Apply coupon', style: TextStyle(fontWeight: FontWeight.w900)),
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

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final theme = Theme.of(context);

    final media = MediaQuery.of(context);
    final screenWidth = media.size.width;
    final isTablet = screenWidth >= 600;

    final double fabBottomOffset = kBottomNavigationBarHeight + media.padding.bottom + 16;

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
          backgroundColor: cs.primary,
          foregroundColor: cs.onPrimary,
          child: const Icon(Icons.add_rounded),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
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
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                    child: Row(
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
                          child: Icon(Icons.emoji_events_rounded, color: cs.primary, size: 22),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                l10n.tr('leagues_my_leagues_title'),
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 18,
                                  letterSpacing: -0.3,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _isLoading
                                    ? 'Loading...'
                                    : '${_leagues.length} league${_leagues.length == 1 ? '' : 's'}',
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.45),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                const GlassSearchBar(),
                const SizedBox(height: 4),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: _isLoading
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                CircularProgressIndicator(color: cs.primary),
                                const SizedBox(height: 14),
                                Text(
                                  'Loading leagues...',
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.45),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : _leagues.isEmpty
                            ? _buildEmptyState(context)
                            : _buildLeagueList(context, _leagues, isTablet),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
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
    if (desc.isNotEmpty) pieces.add(desc);
    if (latestAnn != null && latestAnn.title.trim().isNotEmpty) {
      pieces.add(latestAnn.title.trim());
    }
    return pieces.join(' • ');
  }

  Widget _buildLeagueList(BuildContext context, List<League> leagues, bool isTablet) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final viewerUid = _effectiveUserId.trim();
    final authUid = _authUidOrEmpty();

    final media = MediaQuery.of(context);
    final bottomPadding = 16.0 + media.padding.bottom + kBottomNavigationBarHeight;

    final mainAxisExtent = isTablet ? 230.0 : 220.0;

    return GridView.builder(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
      padding: EdgeInsetsDirectional.fromSTEB(16, 8, 16, bottomPadding),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: isTablet ? 2 : 1,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
        mainAxisExtent: mainAxisExtent,
      ),
      itemCount: leagues.length,
      itemBuilder: (context, index) {
        final league = leagues[index];

        final bool isOwner = _isOwnerForViewer(league, authUid.isNotEmpty ? authUid : viewerUid);
        final bool viewerIsParticipant = _viewerIsParticipantByLeagueId[league.id] ?? false;
        final bool viewerIsViewerOnly = !isOwner && !viewerIsParticipant;

        final registered = _participantCounts[league.id] ?? 0;
        final isFull = registered >= league.maxTeams;

        final requiresPaidLeague =
            league.format == LeagueFormat.uclGroup || league.format == LeagueFormat.uclSwiss;

        final isClassic = league.format == LeagueFormat.classic;

        final classicFullViewerRequiresUnlock =
            isClassic && isFull && !isOwner && !viewerIsParticipant;

        final requiresUnlock = (requiresPaidLeague && !isOwner) || classicFullViewerRequiresUnlock;

        final unlocked = _viewerChargesPaid[league.id] ?? false;
        final showLockedBadge = requiresUnlock && !unlocked;

        final latestAnn = _latestAnnouncements[league.id];

        final subtitle = _buildCardSubtitle(
          context: context,
          league: league,
          registered: registered,
          latestAnn: latestAnn,
        );

        final payingThis = _payingLeagueId == league.id;

        return Stack(
          children: [
            LeagueFlipCard(
              leagueName: league.name,
              leagueCode: league.code.isNotEmpty ? league.code : league.id.substring(0, 8),
              distribution: "${l10n.tr(league.format.l10nKey)} • ${league.season}",
              subtitle: subtitle,
              imageUrl: league.leagueImageUrl,
              isLocked: showLockedBadge,
              onPay: showLockedBadge ? () => _payChargesForLeague(context, league) : null,
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
                      color: Colors.white.withOpacity(0.65),
                      bg: Colors.white.withOpacity(0.08),
                      border: Colors.white.withOpacity(0.15),
                    ),
                  if ((isOwner || viewerIsViewerOnly) && showLockedBadge) const SizedBox(height: 6),
                  if (showLockedBadge)
                    _CardBadge(
                      label: l10n.tr('leagues_badge_locked'),
                      icon: Icons.lock_outline_rounded,
                      color: _premiumAmber,
                      bg: _premiumAmber.withOpacity(0.14),
                      border: _premiumAmber.withOpacity(0.40),
                    ),
                ],
              ),
            ),

            if (showLockedBadge)
              PositionedDirectional(
                bottom: 14,
                end: 14,
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: payingThis ? null : () => _payChargesForLeague(context, league),
                    borderRadius: BorderRadius.circular(20),
                    child: Ink(
                      height: 32,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        gradient: LinearGradient(
                          colors: [
                            _premiumAmber,
                            _premiumAmber.withOpacity(0.80),
                          ],
                        ),
                      ),
                      child: Center(
                        child: payingThis
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                              )
                            : Text(
                                l10n.tr('leagues_pay_button'),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 11,
                                  color: Colors.black,
                                ),
                              ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final media = MediaQuery.of(context);
    final bottomPadding = 16.0 + media.padding.bottom + kBottomNavigationBarHeight;

    return Center(
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: EdgeInsetsDirectional.fromSTEB(24, 24, 24, bottomPadding),
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
                child: Icon(Icons.emoji_events_rounded, size: 36, color: cs.primary),
              ),
              const SizedBox(height: 20),
              Text(
                l10n.tr('leagues_empty_title'),
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                  fontSize: 20,
                  letterSpacing: -0.3,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              Text(
                l10n.tr('leagues_empty_subtitle'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.50),
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
                    onTap: () => _showOptions(context),
                    borderRadius: BorderRadius.circular(16),
                    child: Ink(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        gradient: LinearGradient(
                          colors: [cs.primary, cs.primary.withOpacity(0.75)],
                        ),
                      ),
                      child: Center(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.add_rounded, color: Colors.white, size: 20),
                            const SizedBox(width: 8),
                            Text(
                              l10n.tr('leagues_empty_cta'),
                              style: const TextStyle(
                                color: Colors.white,
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
    final media = MediaQuery.of(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        padding: const EdgeInsets.all(16),
        child: SafeArea(
          minimum: EdgeInsets.only(bottom: media.padding.bottom + kBottomNavigationBarHeight),
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
                      margin: const EdgeInsets.only(top: 12, bottom: 14),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.25),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: Text(
                        l10n.tr('leagues_options_title'),
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                          fontSize: 18,
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    _OptionTile(
                      icon: Icons.add_rounded,
                      iconBg: cs.primary,
                      title: l10n.tr('leagues_options_create_title'),
                      subtitle: l10n.tr('leagues_options_create_subtitle'),
                      onTap: () async {
                        context.pop();
                        await context.push('/leagues/create');
                        // ignore: discarded_futures
                        _refreshLeagues();
                      },
                    ),
                    Divider(color: Colors.white.withOpacity(0.06), height: 1, indent: 16, endIndent: 16),
                    _OptionTile(
                      icon: Icons.qr_code_scanner_rounded,
                      iconBg: Colors.teal,
                      title: l10n.tr('leagues_options_join_qr_title'),
                      subtitle: l10n.tr('leagues_options_join_qr_subtitle'),
                      onTap: () async {
                        context.pop();
                        await context.push('/leagues/join-scanner');
                        if (mounted) {
                          // ignore: discarded_futures
                          _refreshLeagues();
                        }
                      },
                    ),
                    Divider(color: Colors.white.withOpacity(0.06), height: 1, indent: 16, endIndent: 16),
                    _OptionTile(
                      icon: Icons.key_rounded,
                      iconBg: Colors.deepPurple,
                      title: l10n.tr('leagues_options_join_id_title'),
                      subtitle: l10n.tr('leagues_options_join_id_subtitle'),
                      onTap: () async {
                        context.pop();
                        await _showJoinByIdSheet(context);
                        if (mounted) {
                          // ignore: discarded_futures
                          _refreshLeagues();
                        }
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
              settings: LeagueSettings.defaultsFor(LeagueFormat.classic).copyWith(lastPulledAtMs: now),
              updatedAtMs: now,
              version: 1,
            );
          },
        );

        final Membership? membership = await repo.getMembership(leagueId: league.id, userId: authUid);
        final effectiveMode = (membership != null) ? LeagueJoinMode.participant : LeagueJoinMode.viewer;

        if (!context.mounted) return;
        Navigator.of(context).pop();

        if (!context.mounted) return;

        String message;
        final bool adminAlreadyAdded = membership != null && (membership.teamId?.trim().isNotEmpty == true);

        if (adminAlreadyAdded) {
          message = (mode == LeagueJoinMode.viewer)
              ? l10n.tr('leagues_join_snackbar_viewer_but_already_added')
              : l10n.tr('leagues_join_snackbar_already_added');
        } else if (membership != null) {
          message = (mode == LeagueJoinMode.viewer)
              ? l10n.tr('leagues_join_snackbar_viewer_but_already_registered')
              : l10n.tr('leagues_join_snackbar_already_registered');
        } else if (mode == LeagueJoinMode.participant && effectiveMode == LeagueJoinMode.viewer) {
          message = l10n.tr('leagues_join_snackbar_league_full_joined_viewer');
        } else if (mode == LeagueJoinMode.viewer) {
          message = l10n.tr('leagues_join_snackbar_joined_viewer');
        } else {
          message = l10n.tr('leagues_join_snackbar_joined_participant');
        }

        _snack(message);
      } catch (e) {
        setModalState(() {
          joining = false;
          error = UserFriendlyError.toMessage(e is Object ? e : Exception('unknown'));
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
          final bottomInset = MediaQuery.of(ctx).viewInsets.bottom;

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
                                  color: Colors.white.withOpacity(0.25),
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
                                child: Icon(Icons.key_rounded, color: cs.primary, size: 24),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                l10n.tr('leagues_join_sheet_title'),
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 18,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                l10n.tr('leagues_join_sheet_subtitle'),
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.50),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 16),
                              TextField(
                                controller: controller,
                                autofocus: true,
                                textCapitalization: TextCapitalization.characters,
                                style: const TextStyle(fontWeight: FontWeight.w800),
                                decoration: InputDecoration(
                                  hintText: l10n.tr('leagues_join_hint'),
                                  prefixIcon: const Icon(Icons.key_rounded),
                                  errorText: error,
                                ),
                                onChanged: (_) {
                                  if (error != null) setModalState(() => error = null);
                                },
                              ),
                              const SizedBox(height: 14),
                              Glass(
                                borderRadius: 18,
                                padding: const EdgeInsets.all(14),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      l10n.tr('leagues_join_as_title'),
                                      style: theme.textTheme.bodyMedium?.copyWith(
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: _ModeChip(
                                            label: l10n.tr('leagues_join_participant'),
                                            icon: Icons.sports_soccer_rounded,
                                            selected: mode == LeagueJoinMode.participant,
                                            onTap: joining
                                                ? null
                                                : () => setModalState(() => mode = LeagueJoinMode.participant),
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: _ModeChip(
                                            label: l10n.tr('leagues_join_viewer_only'),
                                            icon: Icons.visibility_rounded,
                                            selected: mode == LeagueJoinMode.viewer,
                                            onTap: joining ? null : () => setModalState(() => mode = LeagueJoinMode.viewer),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      mode == LeagueJoinMode.viewer
                                          ? l10n.tr('leagues_join_as_viewer_description')
                                          : l10n.tr('leagues_join_as_participant_description'),
                                      style: TextStyle(
                                        color: Colors.white.withOpacity(0.45),
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
                                    child: Material(
                                      color: Colors.transparent,
                                      child: InkWell(
                                        onTap: joining ? null : () => Navigator.of(ctx).pop(),
                                        borderRadius: BorderRadius.circular(14),
                                        child: Ink(
                                          height: 46,
                                          decoration: BoxDecoration(
                                            borderRadius: BorderRadius.circular(14),
                                            border: Border.all(color: Colors.white.withOpacity(0.12)),
                                          ),
                                          child: Center(
                                            child: Text(
                                              l10n.tr('common_cancel'),
                                              style: TextStyle(
                                                color: Colors.white.withOpacity(0.6),
                                                fontWeight: FontWeight.w800,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Material(
                                      color: Colors.transparent,
                                      child: InkWell(
                                        onTap: joining ? null : () => doJoin(setModalState),
                                        borderRadius: BorderRadius.circular(14),
                                        child: Ink(
                                          height: 46,
                                          decoration: BoxDecoration(
                                            borderRadius: BorderRadius.circular(14),
                                            gradient: LinearGradient(
                                              colors: [
                                                cs.primary,
                                                cs.primary.withOpacity(0.75),
                                              ],
                                            ),
                                          ),
                                          child: Center(
                                            child: joining
                                                ? const SizedBox(
                                                    width: 18,
                                                    height: 18,
                                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                                  )
                                                : Row(
                                                    mainAxisSize: MainAxisSize.min,
                                                    children: [
                                                      const Icon(Icons.login_rounded, size: 18, color: Colors.white),
                                                      const SizedBox(width: 8),
                                                      Text(
                                                        l10n.tr('common_join'),
                                                        style: const TextStyle(
                                                          color: Colors.white,
                                                          fontWeight: FontWeight.w800,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                          ),
                                        ),
                                      ),
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
                        ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.45),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: Colors.white.withOpacity(0.25), size: 20),
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
    final color = selected ? cs.primary : Colors.white.withOpacity(0.5);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: selected ? cs.primary.withOpacity(0.12) : Colors.white.withOpacity(0.04),
          border: Border.all(
            color: selected ? cs.primary.withOpacity(0.30) : Colors.white.withOpacity(0.08),
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
