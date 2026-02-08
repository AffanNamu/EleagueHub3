import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../../core/locale/app_localizations.dart';
import '../../../core/persistence/prefs_service.dart';
import '../../../core/services/notification_service.dart';
import '../../../core/services/sync_trigger.dart';
import '../../../core/widgets/glass.dart';
import '../../../core/widgets/glass_scaffold.dart';
import '../../auth/data/user_profile_repository.dart';
import '../data/league_announcements_local.dart';
import '../data/league_spaces_local.dart';
import '../data/leagues_repository_local.dart';
import '../logic/league_creation_payment_service.dart';
import '../models/league.dart';
import '../models/league_announcement.dart';
import '../models/league_format.dart';
import '../models/league_space.dart';
import '../models/team.dart';
import '../utils/current_user.dart';
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
  late LocalLeaguesRepository _localRepo;
  late LeagueAnnouncementsFirebase _annRepo;
  late LeagueSpacesFirebase _spaceRepo;

  League? _league;
  LeagueSpace? _space;

  bool _isLeagueLoading = true;
  bool _isSyncing = false;
  bool _exportingRoster = false;

  bool _showAddMeAsParticipant = false;
  bool _addingMeAsParticipant = false;

  bool _processingUpgradePayment = false;

  String _currentUserId = '';

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

  static const String _couponAlphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  final Random _couponRnd = Random.secure();

  String _couponCode() {
    final token = List.generate(12, (_) => _couponAlphabet[_couponRnd.nextInt(_couponAlphabet.length)]).join();
    return 'EH$token';
  }

  bool _isOrganizer(League league) => _currentUserId.isNotEmpty && league.organizerUserId == _currentUserId;

  String _couponSubtitle(League league) {
    if (!league.hasCoupons) return 'Not enabled';
    if (league.couponDiscountPercent >= 100) return 'Free access (100%)';
    return '${league.couponDiscountPercent}% discount';
  }

  String _upgradeSubtitle(League league) {
    final viewers = league.viewerCapacity;
    final coupons = league.couponCount;
    final couponPart = league.hasCoupons ? 'Coupons: $coupons' : 'Coupons: none';
    return 'Viewer access: $viewers • $couponPart';
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
      if (counts.containsKey(g)) {
        counts[g] = (counts[g] ?? 0) + 1;
      }
    }

    final available = counts.entries.where((e) => e.value < 4).toList();
    if (available.isEmpty) return null;

    available.sort((a, b) => a.value.compareTo(b.value));
    final min = available.first.value;
    final minGroups = available.where((e) => e.value == min).map((e) => e.key).toList();

    final rnd = Random.secure();
    return minGroups[rnd.nextInt(minGroups.length)];
  }

  @override
  void initState() {
    super.initState();
    final prefs = ref.read(prefsServiceProvider);
    _localRepo = LocalLeaguesRepository(prefs);
    _annRepo = LeagueAnnouncementsFirebase(prefs);
    _spaceRepo = LeagueSpacesFirebase(prefs);
    _loadLeague();

    // ignore: discarded_futures
    SyncTrigger.trySync().then((_) => _loadLeague());
  }

  Future<void> _loadLeague() async {
    final league = await _localRepo.getLeagueById(widget.leagueId);
    final space = await _spaceRepo.getSpace(widget.leagueId);

    bool showAddMe = false;
    String currentUserId = '';

    try {
      currentUserId = await CurrentUser.getUserId();
      final isOrganizer = league != null && league.organizerUserId == currentUserId;

      if (isOrganizer) {
        final teams = await _localRepo.getTeams(widget.leagueId);
        final alreadyParticipant = teams.any((t) => t.id == currentUserId);
        showAddMe = !alreadyParticipant;
      }
    } catch (_) {
      showAddMe = false;
      currentUserId = '';
    }

    if (!mounted) return;
    setState(() {
      _league = league;
      _space = space;
      _currentUserId = currentUserId;
      _showAddMeAsParticipant = showAddMe;
      _isLeagueLoading = false;
    });
  }

  Future<void> _purchaseViewerAccessOrCoupons() async {
    final league = _league;
    if (league == null) return;

    if (_processingUpgradePayment) return;

    if (!_isOrganizer(league)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Only the organizer can purchase add-ons.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() => _processingUpgradePayment = true);

    try {
      final result = await context.push<LeagueCreationPaymentResult?>(
        '/leagues/${league.id}/upgrade/payment',
        extra: <String, dynamic>{
          'leagueId': league.id,
          'leagueName': league.name,
          'addonsOnly': true,
          'existingViewerCapacity': league.viewerCapacity,
          'existingCouponCount': league.couponCount,
          'existingCouponDiscountPercent': league.couponDiscountPercent,
          'existingCouponsEnabled': league.couponsEnabled,
        },
      );

      if (!mounted) return;

      if (result == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Payment cancelled.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }

      if (!result.success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.errorMessage ?? 'Payment failed'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }

      final addViewers = result.viewerCapacity < 0 ? 0 : result.viewerCapacity;
      final addCoupons = result.buyCouponsForParticipants ? (result.couponCount < 0 ? 0 : result.couponCount) : 0;

      final nextViewerCapacity = league.viewerCapacity + addViewers;

      final nextCouponsEnabled = league.couponsEnabled || result.buyCouponsForParticipants;
      final nextCouponPercent =
          result.buyCouponsForParticipants ? result.couponDiscountPercent : league.couponDiscountPercent;
      final nextCouponCount = league.couponCount + addCoupons;

      final now = DateTime.now().millisecondsSinceEpoch;

      final updated = league.copyWith(
        viewerCapacity: nextViewerCapacity,
        couponsEnabled: nextCouponsEnabled,
        couponDiscountPercent: nextCouponPercent,
        couponCount: nextCouponCount,
        updatedAtMs: now,
      );

      await _localRepo.saveLeague(updated);

      await SyncTrigger.trySync();
      await _loadLeague();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Purchase successful. Syncing updates...'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Upgrade purchase failed: $e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _processingUpgradePayment = false);
    }
  }

  Future<String> _createOneCouponRemote({
    required League league,
  }) async {
    final discountPercent = league.couponDiscountPercent;
    if (!league.hasCoupons || discountPercent <= 0) {
      throw StateError('Coupons are not enabled for this league.');
    }

    await SyncTrigger.trySync(timeout: const Duration(seconds: 12));

    final userId = await CurrentUser.getUserId();

    final firestore = FirebaseFirestore.instance;
    final leagueRef = firestore.collection('leagues').doc(league.id);

    final leagueSnap = await leagueRef.get();
    if (!leagueSnap.exists) {
      throw StateError('League not found in cloud yet. Tap Sync now and try again.');
    }

    final leagueData = leagueSnap.data() ?? <String, dynamic>{};
    final remoteOrganizer = (leagueData['organizerUserId'] as String?)?.trim() ?? '';
    final remoteOwner = (leagueData['ownerId'] as String?)?.trim() ?? '';

    final now = DateTime.now().millisecondsSinceEpoch;

    for (int attempt = 0; attempt < 6; attempt++) {
      final code = _couponCode();
      final couponRef = leagueRef.collection('coupons').doc(code);

      try {
        await firestore.runTransaction((tx) async {
          final snap = await tx.get(couponRef);
          if (snap.exists) {
            throw StateError('collision');
          }

          tx.set(couponRef, <String, dynamic>{
            'leagueId': league.id,
            'code': code,
            'organizerUserId': userId,
            'discountPercent': discountPercent,
            'usedBy': '',
            'usedAtMs': 0,
            'reservedBy': '',
            'reservedAt': null,
            'reservedUntil': null,
            'createdAtMs': now,
            'updatedAtMs': now,
            'version': 1,
          });
        });

        return code;
      } on FirebaseException catch (e) {
        if (e.code == 'permission-denied') {
          throw StateError(
            'Permission denied by Firestore rules.\n'
            'Debug:\n'
            '- currentUid: $userId\n'
            '- league.organizerUserId (cloud): $remoteOrganizer\n'
            '- league.ownerId (cloud): $remoteOwner\n'
            'Fix:\n'
            '- Publish the updated firestore.rules\n'
            '- Tap Sync now in League Admin\n',
          );
        }
        rethrow;
      } on StateError catch (e) {
        if (e.message == 'collision') continue;
        rethrow;
      }
    }

    throw StateError('Failed to generate a unique coupon. Try again.');
  }

  void _showCouponsSheet() {
    final league = _league;
    if (league == null) return;

    if (!league.hasCoupons) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Coupons are not enabled for this league.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        bool generating = false;

        final theme = Theme.of(ctx);
        final cs = theme.colorScheme;
        final onSurface = cs.onSurface;

        final couponsQuery = FirebaseFirestore.instance
            .collection('leagues')
            .doc(league.id)
            .collection('coupons')
            .orderBy('createdAtMs', descending: true)
            .limit(100);

        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
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
                              '${league.name} • ${_couponSubtitle(league)}',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: onSurface.withOpacity(0.70),
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton(
                                    onPressed: generating
                                        ? null
                                        : () async {
                                            setModalState(() => generating = true);
                                            try {
                                              final code = await _createOneCouponRemote(league: league);
                                              if (!mounted) return;
                                              await Clipboard.setData(ClipboardData(text: code));
                                              if (!mounted) return;
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                SnackBar(
                                                  content: Text('Coupon generated & copied: $code'),
                                                  behavior: SnackBarBehavior.floating,
                                                ),
                                              );
                                            } catch (e) {
                                              if (!mounted) return;
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                SnackBar(
                                                  content: Text('$e'),
                                                  behavior: SnackBarBehavior.floating,
                                                ),
                                              );
                                            } finally {
                                              setModalState(() => generating = false);
                                            }
                                          },
                                    child: generating
                                        ? const SizedBox(
                                            width: 18,
                                            height: 18,
                                            child: CircularProgressIndicator(strokeWidth: 2),
                                          )
                                        : const Text('Generate & copy'),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: FilledButton(
                                    onPressed: () => Navigator.of(ctx).pop(),
                                    child: const Text('Close'),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Divider(color: onSurface.withOpacity(0.12)),
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxHeight: 420),
                              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                                stream: couponsQuery.snapshots(),
                                builder: (context, snap) {
                                  if (snap.hasError) {
                                    return Center(
                                      child: Text(
                                        'Failed to load coupons.',
                                        style: theme.textTheme.bodyMedium?.copyWith(
                                          color: cs.error,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    );
                                  }

                                  if (!snap.hasData) {
                                    return Center(child: CircularProgressIndicator(color: cs.primary));
                                  }

                                  final docs = snap.data!.docs;

                                  if (docs.isEmpty) {
                                    return Center(
                                      child: Text(
                                        'No coupons yet. If you just created the league, tap Sync and try again.',
                                        textAlign: TextAlign.center,
                                        style: theme.textTheme.bodySmall?.copyWith(
                                          color: onSurface.withOpacity(0.70),
                                          fontWeight: FontWeight.w600,
                                          height: 1.35,
                                        ),
                                      ),
                                    );
                                  }

                                  return ListView.separated(
                                    itemCount: docs.length,
                                    separatorBuilder: (_, __) => Divider(color: onSurface.withOpacity(0.10)),
                                    itemBuilder: (context, i) {
                                      final d = docs[i].data();
                                      final code = (d['code'] as String?)?.trim().isNotEmpty == true
                                          ? (d['code'] as String).trim()
                                          : docs[i].id;
                                      final usedBy = (d['usedBy'] as String?)?.trim() ?? '';
                                      final isUsed = usedBy.isNotEmpty;

                                      return ListTile(
                                        dense: true,
                                        contentPadding: EdgeInsets.zero,
                                        leading: Icon(
                                          isUsed ? Icons.check_circle : Icons.confirmation_number_outlined,
                                          color: isUsed ? const Color(0xFF22C55E) : cs.primary,
                                          size: 20,
                                        ),
                                        title: Text(
                                          code,
                                          style: theme.textTheme.bodyMedium?.copyWith(
                                            color: onSurface,
                                            fontWeight: FontWeight.w900,
                                          ),
                                        ),
                                        subtitle: Text(
                                          isUsed ? 'Used' : 'Unused',
                                          style: theme.textTheme.bodySmall?.copyWith(
                                            color: onSurface.withOpacity(0.65),
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        trailing: IconButton(
                                          tooltip: 'Copy',
                                          icon: Icon(Icons.copy, color: onSurface.withOpacity(0.72), size: 18),
                                          onPressed: () async {
                                            await Clipboard.setData(ClipboardData(text: code));
                                            if (!mounted) return;
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              SnackBar(
                                                content: Text('Copied: $code'),
                                                behavior: SnackBarBehavior.floating,
                                              ),
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

  // --- the rest of the admin screen (unchanged) ---

  Future<void> _addMeAsParticipant() async {
    final l10n = context.l10n;
    final league = _league;
    if (league == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.tr('league_admin_league_info_not_loaded_yet')),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    if (_addingMeAsParticipant) return;

    setState(() => _addingMeAsParticipant = true);

    try {
      final userId = await CurrentUser.getUserId();

      if (league.organizerUserId != userId) {
        throw StateError(l10n.tr('league_admin_only_organizer_action'));
      }

      if (league.format == LeagueFormat.uclGroup && !(league.maxTeams == 16 || league.maxTeams == 32)) {
        throw StateError(l10n.tr('league_admin_ucl_group_maxteams_error'));
      }
      if (league.format == LeagueFormat.uclSwiss && !(league.maxTeams == 18 || league.maxTeams == 36)) {
        throw StateError(l10n.tr('league_admin_swiss_maxteams_error'));
      }

      final existingTeams = await _localRepo.getTeams(league.id);
      final alreadyHasTeam = existingTeams.any((t) => t.id == userId);
      if (alreadyHasTeam) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.tr('league_admin_already_added_participant_team_exists')),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }

      if (existingTeams.length >= league.maxTeams) {
        throw StateError(
          '${l10n.tr('league_admin_league_full_prefix')}${league.maxTeams}${l10n.tr('league_admin_league_full_suffix')}',
        );
      }

      final profile = await UserProfileRepository().fetchByUserId(userId);
      final teamName = profile?.teamName.trim() ?? '';
      if (teamName.isEmpty) {
        throw StateError(l10n.tr('league_admin_profile_team_name_missing'));
      }

      String? groupId;
      if (league.format == LeagueFormat.uclGroup) {
        final allowedGroups = _allowedGroupsForUclGroup(league);
        final picked = _pickGroupWithSpace(teams: existingTeams, allowedGroups: allowedGroups);
        if (picked == null) {
          throw StateError(l10n.tr('league_admin_all_groups_full'));
        }
        groupId = picked;
      } else {
        groupId = null;
      }

      final now = DateTime.now().millisecondsSinceEpoch;

      final team = Team(
        id: userId,
        leagueId: league.id,
        name: teamName,
        groupId: groupId,
        updatedAtMs: now,
        version: 1,
      );

      await _localRepo.saveTeams(league.id, <Team>[...existingTeams, team]);

      await _localRepo.assignTeamToUserInLeague(
        leagueId: league.id,
        userId: userId,
        teamId: userId,
      );

      if (!mounted) return;

      await _loadLeague();

      final msg = groupId == null
          ? l10n.tr('league_admin_added_participant')
          : '${l10n.tr('league_admin_added_participant_in_group_prefix')} ${_groupDisplayName(l10n, groupId)}.';

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${l10n.tr('league_admin_failed_add_participant_prefix')} $e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _addingMeAsParticipant = false);
    }
  }

  Future<void> _exportRosterCsv() async {
    final l10n = context.l10n;
    final league = _league;
    if (league == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.tr('league_admin_league_info_not_loaded_yet')),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    if (_exportingRoster) return;

    setState(() => _exportingRoster = true);
    try {
      await RosterCsvExporter.shareRosterCsv(
        repo: _localRepo,
        league: league,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${l10n.tr('league_admin_export_failed_prefix')} $e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _exportingRoster = false);
    }
  }

  Future<void> _syncParticipants() async {
    final l10n = context.l10n;

    setState(() => _isSyncing = true);
    await SyncTrigger.trySync();
    if (!mounted) return;
    setState(() => _isSyncing = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l10n.tr('league_admin_sync_complete')),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return GlassScaffold(
      appBar: AppBar(
        title: Text(l10n.tr('league_admin_appbar_title')),
        backgroundColor: Colors.transparent,
        elevation: 0,
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
                        ? Center(child: CircularProgressIndicator(color: cs.primary))
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

    final title = widget.hasPendingChanges ? l10n.tr('league_admin_offline_changes_title') : l10n.tr('league_admin_fully_synced_title');

    final subtitle =
        widget.hasPendingChanges ? l10n.tr('league_admin_offline_changes_subtitle') : l10n.tr('league_admin_fully_synced_subtitle');

    final statusIcon = widget.hasPendingChanges ? Icons.cloud_off : Icons.cloud_done;
    final statusColor = widget.hasPendingChanges ? const Color(0xFFF59E0B) : const Color(0xFF22C55E);

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
              tooltip: l10n.tr('league_admin_sync_now_tooltip'),
              onPressed: () async {
                await SyncTrigger.trySync();
                await _loadLeague();
              },
              icon: Icon(Icons.sync, color: cs.onSurface.withOpacity(0.72)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingsList(BuildContext context) {
    final l10n = context.l10n;
    final spaceLive = _space?.isLive == true;

    final league = _league;

    return ListView(
      children: [
        if (league != null && _isOrganizer(league))
          _buildSettingsTile(
            context,
            Icons.payments_outlined,
            _processingUpgradePayment ? 'Processing payment...' : 'Buy viewer access / coupons',
            _upgradeSubtitle(league),
            onTap: _processingUpgradePayment ? null : _purchaseViewerAccessOrCoupons,
          ),
        if (league != null && league.hasCoupons)
          _buildSettingsTile(
            context,
            Icons.confirmation_number_outlined,
            'Coupons',
            _couponSubtitle(league),
            onTap: _showCouponsSheet,
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
            _addingMeAsParticipant ? l10n.tr('league_admin_adding_you') : l10n.tr('league_admin_add_me_participant'),
            l10n.tr('league_admin_add_me_participant_subtitle'),
            onTap: _addingMeAsParticipant ? null : _addMeAsParticipant,
          ),
        _buildSettingsTile(
          context,
          Icons.file_download_outlined,
          _exportingRoster ? l10n.tr('league_admin_exporting_roster') : l10n.tr('league_admin_export_roster'),
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
                builder: (_) => LeagueParticipantsScreen(leagueId: widget.leagueId),
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
          spaceLive ? l10n.tr('league_admin_league_space_live') : l10n.tr('league_admin_league_space_voice_room'),
          spaceLive ? l10n.tr('league_admin_league_space_live_subtitle') : l10n.tr('league_admin_league_space_voice_room_subtitle'),
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
          Icons.sync,
          l10n.tr('league_admin_sync_now'),
          _isSyncing ? l10n.tr('league_admin_syncing') : l10n.tr('league_admin_sync_now_subtitle'),
          onTap: _isSyncing ? null : _syncParticipants,
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
            trailing: Icon(chevronIcon, color: cs.onSurface.withOpacity(0.30)),
            onTap: onTap,
          ),
        ),
      ),
    );
  }

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
                        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12),
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
                              onChanged: (v) => setModalState(() => chatEnabled = v),
                              activeColor: cs.primary,
                              title: Text(
                                l10n.tr('league_admin_viewer_text_chat'),
                                style: TextStyle(color: onSurface, fontWeight: FontWeight.w800),
                              ),
                              subtitle: Text(
                                l10n.tr('league_admin_viewer_text_chat_subtitle'),
                                style: TextStyle(color: onSurface.withOpacity(0.65), fontSize: 12, fontWeight: FontWeight.w600),
                              ),
                            ),
                            SwitchListTile.adaptive(
                              value: voiceEnabled,
                              onChanged: (v) => setModalState(() => voiceEnabled = v),
                              activeColor: cs.primary,
                              title: Text(
                                l10n.tr('league_admin_viewer_audio'),
                                style: TextStyle(color: onSurface, fontWeight: FontWeight.w800),
                              ),
                              subtitle: Text(
                                l10n.tr('league_admin_viewer_audio_subtitle'),
                                style: TextStyle(color: onSurface.withOpacity(0.65), fontSize: 12, fontWeight: FontWeight.w600),
                              ),
                            ),
                            SwitchListTile.adaptive(
                              value: reactionsEnabled,
                              onChanged: (v) => setModalState(() => reactionsEnabled = v),
                              activeColor: cs.primary,
                              title: Text(
                                l10n.tr('league_admin_viewer_reactions'),
                                style: TextStyle(color: onSurface, fontWeight: FontWeight.w800),
                              ),
                              subtitle: Text(
                                l10n.tr('league_admin_viewer_reactions_subtitle'),
                                style: TextStyle(color: onSurface.withOpacity(0.65), fontSize: 12, fontWeight: FontWeight.w600),
                              ),
                            ),
                            Align(
                              alignment: Alignment.centerRight,
                              child: Padding(
                                padding: const EdgeInsets.only(top: 8, right: 4, bottom: 8),
                                child: FilledButton(
                                  onPressed: () async {
                                    await prefs.setLiveViewerChatEnabled(chatEnabled);
                                    await prefs.setLiveViewerVoiceEnabled(voiceEnabled);
                                    await prefs.setLiveViewerReactionsEnabled(reactionsEnabled);

                                    if (!mounted) return;
                                    Navigator.of(ctx).pop();
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(l10n.tr('league_admin_live_viewer_settings_updated')),
                                        behavior: SnackBarBehavior.floating,
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

  void _showLeagueSpaceAdminSheet() {
    final l10n = context.l10n;
    final leagueName = _league?.name ?? l10n.tr('common_league_placeholder');
    final spaceLive = _space?.isLive == true;

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
                constraints: const BoxConstraints(maxWidth: 520),
                child: Glass(
                  borderRadius: 28,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          l10n.tr('league_admin_league_space_sheet_title'),
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: onSurface,
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          spaceLive
                              ? '${l10n.tr('league_admin_league_space_running_prefix')} $leagueName.'
                              : '${l10n.tr('league_admin_league_space_start_description_prefix')} $leagueName${l10n.tr('league_admin_league_space_start_description_suffix')}',
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
                                  onPressed: () => Navigator.of(ctx).pop(),
                                  child: Text(l10n.tr('profile_close_tooltip')),
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
                                  label: Text(l10n.tr('league_admin_start_space')),
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
                                  label: Text(l10n.tr('league_admin_open_space')),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: FilledButton.icon(
                                  style: FilledButton.styleFrom(backgroundColor: cs.error),
                                  onPressed: () {
                                    Navigator.of(ctx).pop();
                                    _endSpace();
                                  },
                                  icon: const Icon(Icons.stop_circle_outlined),
                                  label: Text(l10n.tr('league_admin_end_space')),
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

  void _showSendAnnouncementSheet() {
    final l10n = context.l10n;

    if (_league == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.tr('league_admin_league_info_not_loaded_yet')),
          behavior: SnackBarBehavior.floating,
        ),
      );
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
            padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom).add(const EdgeInsets.all(16)),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Glass(
                  borderRadius: 28,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          l10n.tr('league_admin_send_announcement_sheet_title'),
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: onSurface,
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          l10n.tr('league_admin_send_announcement_sheet_subtitle'),
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
                            labelText: l10n.tr('league_admin_announcement_title_optional'),
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: messageController,
                          maxLines: 3,
                          decoration: InputDecoration(
                            labelText: l10n.tr('league_admin_announcement_message_label'),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: TextButton(
                                onPressed: () => Navigator.of(ctx).pop(),
                                child: Text(l10n.tr('common_cancel')),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: FilledButton(
                                onPressed: () async {
                                  final rawTitle = titleController.text.trim();
                                  final msg = messageController.text.trim();
                                  if (msg.isEmpty) return;

                                  final title = rawTitle.isEmpty ? l10n.tr('league_admin_announcement_default_title') : rawTitle;
                                  final now = DateTime.now().millisecondsSinceEpoch;

                                  final ann = LeagueAnnouncement(
                                    id: _uuid.v4(),
                                    leagueId: widget.leagueId,
                                    title: title,
                                    message: msg,
                                    createdAtMs: now,
                                  );

                                  await _annRepo.addAnnouncement(ann);

                                  await NotificationService().showLeagueAnnouncementNotification(
                                    leagueName: _league?.name ?? l10n.tr('common_league_placeholder'),
                                    title: title,
                                    message: msg,
                                  );

                                  await SyncTrigger.trySync();

                                  if (!mounted) return;
                                  Navigator.of(ctx).pop();
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(l10n.tr('league_admin_announcement_sent')),
                                      behavior: SnackBarBehavior.floating,
                                    ),
                                  );
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
    );
  }

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
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
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
                            child: Icon(Icons.group, color: cs.onPrimary),
                          ),
                          title: Text(
                            l10n.tr('league_admin_teams_add_edit_title'),
                            style: TextStyle(color: onSurface, fontWeight: FontWeight.w900),
                          ),
                          subtitle: Text(
                            l10n.tr('league_admin_teams_add_edit_subtitle'),
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
                            backgroundColor: onSurface.withOpacity(0.08),
                            child: Icon(Icons.people, color: onSurface),
                          ),
                          title: Text(
                            l10n.tr('league_admin_joined_participants_title'),
                            style: TextStyle(color: onSurface, fontWeight: FontWeight.w900),
                          ),
                          subtitle: Text(
                            l10n.tr('league_admin_joined_participants_subtitle'),
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
                              MaterialPageRoute(builder: (_) => LeagueParticipantsScreen(leagueId: widget.leagueId)),
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.tr('league_admin_league_info_not_loaded_yet_try_again')),
          behavior: SnackBarBehavior.floating,
        ),
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

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l10n.tr('league_admin_rules_editor_unchanged')),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _confirmDeleteLeague() {
    final l10n = context.l10n;

    showDialog(
      context: context,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        final cs = theme.colorScheme;
        final onSurface = cs.onSurface;

        return AlertDialog(
          backgroundColor: cs.surface,
          title: Text(
            l10n.tr('league_admin_delete_league_confirm_title'),
            style: TextStyle(color: onSurface, fontWeight: FontWeight.w900),
          ),
          content: Text(
            l10n.tr('league_admin_delete_league_confirm_message'),
            style: TextStyle(color: onSurface.withOpacity(0.72), fontWeight: FontWeight.w600),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(l10n.tr('common_cancel')),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: cs.error),
              onPressed: () async {
                await _localRepo.deleteLeagueCompletely(widget.leagueId);

                if (!mounted) return;
                Navigator.of(ctx).pop();

                GoRouter.of(context).go('/leagues');

                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(l10n.tr('league_admin_league_deleted')),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              },
              child: Text(l10n.tr('league_admin_delete')),
            ),
          ],
        );
      },
    );
  }
}
