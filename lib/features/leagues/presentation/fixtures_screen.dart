import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/user_friendly_error.dart';
import '../../../core/locale/app_localizations.dart';
import '../../../core/persistence/prefs_service.dart';
import '../../../core/services/connectivity_service.dart';
import '../../../core/widgets/glass.dart';
import '../../../core/widgets/glass_scaffold.dart';
import '../../../core/widgets/section_header.dart';
import '../../chat/data/chat_repository.dart';
import '../../chat/models/chat_message.dart';
import '../data/leagues_repository_local.dart';
import '../domain/algorithms/swiss_pairing.dart';
import '../models/enums.dart';
import '../models/fixture_match.dart';
import '../models/league_format.dart';
import '../models/membership.dart';

class FixturesScreen extends ConsumerStatefulWidget {
  final String leagueId;

  const FixturesScreen({
    super.key,
    required this.leagueId,
  });

  @override
  ConsumerState<FixturesScreen> createState() => _FixturesScreenState();
}

class _FixturesScreenState extends ConsumerState<FixturesScreen> {
  int _selectedRound = 1;

  late LocalLeaguesRepository _repo;
  late PreferencesService _prefs;

  final ChatRepository _chatRepo = ChatRepository();

  Map<String, String> _teamNames = {};

  /// teamId -> imageUrl (PRIMARY: user profile image for UID-based teams)
  Map<String, String> _teamImageUrls = {};

  bool _isLoading = true;
  String? _loadError;

  LeagueFormat _format = LeagueFormat.classic;
  List<String> _groups = [];

  /// null = "All groups" when format == uclGroup
  String? _selectedGroup;

  bool _isGeneratingNextRound = false;

  // Organizer guard: only organiser can generate Swiss rounds from this screen.
  bool _isOrganizer = false;

  // Fixtures selection mode (WhatsApp style)
  final ValueNotifier<Set<String>> _selectedFixtureIds = ValueNotifier<Set<String>>(<String>{});
  bool _isSharingFixtures = false;

  List<FixtureMatch> _allMatches = const [];
  int _totalRounds = 0;

  static String _lastRoundKey(String leagueId) => 'ui_last_round_$leagueId';
  static String _lastGroupKey(String leagueId) => 'ui_last_group_$leagueId';

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Prevent repeated expensive lookups.
  final Set<String> _requestedUserImageIds = <String>{};

  static const String _superAdminUid = 'a0JDUelQW3TEyoXTm4ESuGi7ndq1';

  bool get _isSuperAdmin => (FirebaseAuth.instance.currentUser?.uid.trim() ?? '') == _superAdminUid;

  /// Admin-only: selection mode & share.
  /// Uses existing organizer guard + super admin. (No new backend role assumptions.)
  bool get _canAdminSelectFixtures => _isOrganizer || _isSuperAdmin;

  bool get _isSelectionMode => _selectedFixtureIds.value.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _prefs = ref.read(prefsServiceProvider);
    _repo = LocalLeaguesRepository(_prefs);

    final savedRoundRaw = _prefs.getString(_lastRoundKey(widget.leagueId));
    final savedRound = int.tryParse((savedRoundRaw ?? '').trim());
    if (savedRound != null && savedRound >= 1) {
      _selectedRound = savedRound;
    }

    final savedGroupRaw = _prefs.getString(_lastGroupKey(widget.leagueId));
    _selectedGroup = (savedGroupRaw == null || savedGroupRaw.trim().isEmpty) ? null : savedGroupRaw.trim();

    // ignore: discarded_futures
    _loadInitialData();
  }

  void _persistRound(int round) {
    _prefs.setString(_lastRoundKey(widget.leagueId), '$round');
  }

  void _persistGroup(String? group) {
    _prefs.setString(_lastGroupKey(widget.leagueId), group ?? '');
  }

  void _clearSelection() {
    if (_selectedFixtureIds.value.isEmpty) return;
    _selectedFixtureIds.value = <String>{};
  }

  void _setRound(int round) {
    // Switching rounds implicitly exits selection mode (prevents sharing hidden selections).
    _clearSelection();
    setState(() => _selectedRound = round);
    _persistRound(round);
  }

  void _setGroup(String? group) {
    // Switching groups implicitly exits selection mode.
    _clearSelection();
    setState(() {
      _selectedGroup = group;
      _selectedRound = 1;
    });
    _persistGroup(group);
    _persistRound(1);
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

  Color _baseSnackBg(ThemeData theme) {
    return theme.brightness == Brightness.dark ? const Color(0xFF101522) : const Color(0xFF0F172A);
  }

  void _snack(String msg) {
    if (!mounted) return;

    final theme = Theme.of(context);
    final bg = _baseSnackBg(theme);

    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(12),
        backgroundColor: bg,
        content: Text(
          msg,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  int _computeTotalRounds({
    required LeagueFormat format,
    required List<FixtureMatch> matches,
    required String? selectedGroup,
  }) {
    Iterable<FixtureMatch> filtered = matches;

    if (format == LeagueFormat.uclGroup && selectedGroup != null) {
      filtered = filtered.where((m) => m.groupId == selectedGroup);
    }

    final list = filtered.toList();
    if (list.isEmpty) return 0;

    return list.map((m) => m.roundNumber).reduce((a, b) => a > b ? a : b);
  }

  List<FixtureMatch> _matchesForSelectedRound() {
    Iterable<FixtureMatch> filtered = _allMatches;

    if (_format == LeagueFormat.uclGroup && _selectedGroup != null) {
      filtered = filtered.where((m) => m.groupId == _selectedGroup);
    }

    filtered = filtered.where((m) => m.roundNumber == _selectedRound);

    final list = filtered.toList();

    list.sort((a, b) {
      final r = a.sortIndex.compareTo(b.sortIndex);
      if (r != 0) return r;
      return a.id.compareTo(b.id);
    });

    return list;
  }

  bool _looksLikeFirebaseUid(String s) => s.trim().length > 20;

  String _bestUserImageUrlFromUserDoc(Map<String, dynamic> data) {
    final teamImageUrl = (data['teamImageUrl'] as String?)?.trim() ?? '';
    if (teamImageUrl.isNotEmpty) return teamImageUrl;

    final profileImageUrl = (data['profileImageUrl'] as String?)?.trim() ?? '';
    if (profileImageUrl.isNotEmpty) return profileImageUrl;

    final photoUrl = (data['photoUrl'] as String?)?.trim() ?? '';
    if (photoUrl.isNotEmpty) return photoUrl;

    return '';
  }

  Future<Map<String, String>> _fetchUserImagesByIds(List<String> ids) async {
    final clean = ids.map((e) => e.trim()).where((e) => e.isNotEmpty && _looksLikeFirebaseUid(e)).toList(growable: false);
    if (clean.isEmpty) return const <String, String>{};

    final out = <String, String>{};

    const chunkSize = 10; // whereIn limit
    for (var i = 0; i < clean.length; i += chunkSize) {
      final chunk = clean.sublist(i, (i + chunkSize > clean.length) ? clean.length : i + chunkSize);

      final snap = await _firestore
          .collection('users')
          .where(FieldPath.documentId, whereIn: chunk)
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 10));

      for (final d in snap.docs) {
        final url = _bestUserImageUrlFromUserDoc(d.data());
        if (url.trim().isNotEmpty) out[d.id] = url.trim();
      }
    }

    return out;
  }

  Future<void> _ensureUserImagesForTeamIds(List<String> ids) async {
    final missing = <String>[];
    for (final id in ids) {
      final clean = id.trim();
      if (!_looksLikeFirebaseUid(clean)) continue;
      if (_requestedUserImageIds.contains(clean)) continue;

      _requestedUserImageIds.add(clean);

      if ((_teamImageUrls[clean] ?? '').trim().isNotEmpty) continue;
      missing.add(clean);
    }

    if (missing.isEmpty) return;

    try {
      final userImages = await _fetchUserImagesByIds(missing);
      if (!mounted) return;
      if (userImages.isEmpty) return;

      setState(() {
        _teamImageUrls = {..._teamImageUrls, ...userImages};
      });
    } catch (_) {
      // best-effort only
    }
  }

  Map<String, String> _mergePreferExisting(Map<String, String> base, Map<String, String> incoming) {
    if (incoming.isEmpty) return base;
    final out = <String, String>{...base};
    incoming.forEach((k, v) {
      final key = k.trim();
      final val = v.trim();
      if (key.isEmpty || val.isEmpty) return;

      if ((out[key] ?? '').trim().isNotEmpty) return;

      out[key] = val;
    });
    return out;
  }

  Future<void> _loadTeamImagesBestEffortRemoteFromTeamsCollection() async {
    try {
      final snap = await _firestore
          .collection('leagues')
          .doc(widget.leagueId)
          .collection('teams')
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 8));

      final out = <String, String>{};
      for (final d in snap.docs) {
        final data = d.data();
        final id = (data['id'] is String && (data['id'] as String).trim().isNotEmpty) ? (data['id'] as String).trim() : d.id;

        final candidate = (data['teamImageUrl'] as String?)?.trim() ?? '';
        if (id.isNotEmpty && candidate.isNotEmpty) out[id] = candidate;
      }

      if (!mounted) return;
      if (out.isEmpty) return;

      setState(() {
        _teamImageUrls = _mergePreferExisting(_teamImageUrls, out);
      });
    } catch (_) {
      // Best-effort only.
    }
  }

  Future<void> _loadInitialData() async {
    _clearSelection();

    setState(() {
      _isLoading = true;
      _loadError = null;
    });

    try {
      final authUid = FirebaseAuth.instance.currentUser?.uid.trim() ?? '';
      if (authUid.isEmpty) {
        if (mounted) context.go('/login');
        return;
      }

      await ConnectivityService.instance.requireOnline(timeout: const Duration(seconds: 4));

      final league = await _repo.getLeagueById(widget.leagueId).timeout(const Duration(seconds: 20));
      final teams = await _repo.getTeams(widget.leagueId).timeout(const Duration(seconds: 20));
      final allMatches = await _repo.getMatches(widget.leagueId).timeout(const Duration(seconds: 25));

      final format = league?.format ?? LeagueFormat.classic;

      List<String> groups = [];
      if (format == LeagueFormat.uclGroup) {
        groups = allMatches
            .map((m) => m.groupId)
            .whereType<String>()
            .map((g) => g.trim())
            .where((g) => g.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
      }

      String? validatedGroup;
      if (format == LeagueFormat.uclGroup) {
        final g = _selectedGroup;
        if (g != null && g.isNotEmpty && groups.contains(g)) {
          validatedGroup = g;
        } else {
          validatedGroup = null;
        }
      } else {
        validatedGroup = null;
      }

      final totalRounds = _computeTotalRounds(
        format: format,
        matches: allMatches,
        selectedGroup: validatedGroup,
      );

      var roundToUse = _selectedRound;
      if (totalRounds > 0 && roundToUse > totalRounds) roundToUse = totalRounds;
      if (roundToUse < 1) roundToUse = 1;

      Membership? membership;
      try {
        membership = await _repo.getMembership(
          leagueId: widget.leagueId,
          userId: authUid,
        );
      } catch (_) {
        membership = null;
      }

      final isOrganizer = membership?.role == LeagueRole.organizer || (league?.organizerUid.trim() == authUid);

      final localImages = <String, String>{};
      for (final t in teams) {
        final id = t.id.trim();
        final url = t.teamImageUrl.trim();
        if (id.isNotEmpty && url.isNotEmpty) {
          localImages[id] = url;
        }
      }

      if (!mounted) return;
      setState(() {
        _format = format;
        _teamNames = {for (var t in teams) t.id: t.name};
        _teamImageUrls = localImages;
        _groups = groups;
        _selectedGroup = validatedGroup;
        _selectedRound = roundToUse;
        _isOrganizer = isOrganizer;
        _allMatches = allMatches;
        _totalRounds = totalRounds;
        _isLoading = false;
      });

      _persistGroup(_selectedGroup);
      _persistRound(_selectedRound);

      final idsFromMatches = <String>{
        for (final m in allMatches) m.homeTeamId.trim(),
        for (final m in allMatches) m.awayTeamId.trim(),
      }.where((e) => e.isNotEmpty).toList();
      unawaited(_ensureUserImagesForTeamIds(idsFromMatches));

      unawaited(_loadTeamImagesBestEffortRemoteFromTeamsCollection());
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _loadError = UserFriendlyError.toMessage(e is Object ? e : Exception('unknown'));
      });
      _snack(_loadError!);
    }
  }

  Future<void> _generateNextSwissRound() async {
    final l10n = context.l10n;

    if (_isGeneratingNextRound || _format != LeagueFormat.uclSwiss) return;

    if (!_isOrganizer) {
      _snack(l10n.tr('fixtures_only_organiser_can_generate_swiss_rounds'));
      return;
    }

    setState(() => _isGeneratingNextRound = true);
    try {
      final authUid = FirebaseAuth.instance.currentUser?.uid.trim() ?? '';
      if (authUid.isEmpty) {
        if (mounted) context.go('/login');
        return;
      }

      await ConnectivityService.instance.requireOnline(timeout: const Duration(seconds: 4));

      final league = await _repo.getLeagueById(widget.leagueId).timeout(const Duration(seconds: 20));
      if (league == null) {
        _snack(l10n.tr('fixtures_league_not_found'));
        return;
      }

      final maxRounds = league.settings.swissRounds;

      final teams = await _repo.getTeams(widget.leagueId).timeout(const Duration(seconds: 20));

      final n = teams.length;
      if (!(n == 18 || n == 36)) {
        _snack('${l10n.tr('fixtures_swiss_team_count_error_prefix')}$n.');
        return;
      }

      final existingMatches = await _repo.getMatches(widget.leagueId).timeout(const Duration(seconds: 25));

      int currentMaxRound = 0;
      if (existingMatches.isNotEmpty) {
        currentMaxRound = existingMatches.map((m) => m.roundNumber).reduce((a, b) => a > b ? a : b);
      }

      if (currentMaxRound > 0) {
        final currentRoundMatches = existingMatches.where((m) => m.roundNumber == currentMaxRound).toList();
        final anyUnplayed = currentRoundMatches.any((m) => !m.isPlayed);
        if (anyUnplayed) {
          _snack(
            '${l10n.tr('admin_score_complete_round_prefix')}$currentMaxRound'
            '${l10n.tr('admin_score_complete_round_suffix')}',
          );
          return;
        }
      }

      int nextRound;
      List<FixtureMatch> newFixtures;

      if (currentMaxRound == 0) {
        nextRound = 1;
        newFixtures = SwissPairingEngine.generateInitialRound(
          leagueId: widget.leagueId,
          teams: teams,
          roundNumber: nextRound,
          totalRounds: league.settings.swissRounds,
        );
      } else {
        if (currentMaxRound >= maxRounds) {
          _snack(
            '${l10n.tr('admin_score_all_swiss_rounds_generated_prefix')}$maxRounds'
            '${l10n.tr('admin_score_all_swiss_rounds_generated_suffix')}',
          );
          return;
        }

        nextRound = currentMaxRound + 1;

        final alreadyExists = existingMatches.any((m) => m.roundNumber == nextRound);
        if (alreadyExists) {
          _snack(
            '${l10n.tr('admin_score_round_already_exists_prefix')}$nextRound'
            '${l10n.tr('admin_score_round_already_exists_suffix')}',
          );
          return;
        }

        newFixtures = SwissPairingEngine.generateNextRound(
          leagueId: widget.leagueId,
          teams: teams,
          existingMatches: existingMatches,
          nextRoundNumber: nextRound,
          totalRounds: league.settings.swissRounds,
        );
      }

      if (newFixtures.isEmpty) {
        _snack(l10n.tr('fixtures_no_valid_swiss_pairings'));
        return;
      }

      await _repo.saveMatches(widget.leagueId, newFixtures).timeout(const Duration(seconds: 25));

      if (!mounted) return;

      _setRound(nextRound);

      _snack(
        '${l10n.tr('fixtures_swiss_round_generated_prefix')}$nextRound'
        '${l10n.tr('fixtures_swiss_round_generated_suffix')}',
      );

      await _loadInitialData();
    } catch (e) {
      if (mounted) {
        _snack(UserFriendlyError.toMessage(e is Object ? e : Exception('unknown')));
      }
    } finally {
      if (mounted) setState(() => _isGeneratingNextRound = false);
    }
  }

  // ===========================================================================
  // FIXTURE SELECTION + SHARE (ADMIN ONLY)
  // ===========================================================================

  void _toggleFixtureSelection(String matchId) {
    final id = matchId.trim();
    if (id.isEmpty) return;

    final cur = _selectedFixtureIds.value;
    final next = <String>{...cur};
    if (next.contains(id)) {
      next.remove(id);
    } else {
      next.add(id);
    }
    _selectedFixtureIds.value = next;
  }

  Future<void> _handleFixtureTap(FixtureMatch match) async {
    if (_isSelectionMode) {
      _toggleFixtureSelection(match.id);
      return;
    }

    final matchDetailsRoute = '/leagues/${widget.leagueId}/matches/${match.id}';

    final statusName = match.status.toString().toLowerCase();
    final isStreaming = statusName.contains('stream');

    if (isStreaming) {
      final streamRoute = '/leagues/${widget.leagueId}/matches/${match.id}/stream';
      try {
        await context.push(streamRoute);
        return;
      } catch (_) {
        // fallback safely
      }
    }

    await context.push(matchDetailsRoute);
  }

  void _handleFixtureLongPress(FixtureMatch match) {
    if (!_canAdminSelectFixtures) return;
    HapticFeedback.mediumImpact();
    _toggleFixtureSelection(match.id);
  }

  String _fallbackSenderName(User user) {
    final dn = (user.displayName ?? '').trim();
    if (dn.isNotEmpty) return dn;
    final email = (user.email ?? '').trim();
    if (email.isNotEmpty) return email.split('@').first;
    return 'Admin';
  }

  String _fallbackSenderPhoto(User user) => (user.photoURL ?? '').trim();

  /// REQUIRED CHANGE:
  /// Share message should contain ONLY the team names in the format:
  ///   Barcelona vs Madrid
  /// and for multiple selections, one per line.
  String _shareFixturesMessage(List<FixtureMatch> matches) {
    final l10n = context.l10n;

    final sorted = [...matches];
    sorted.sort((a, b) {
      final r = a.roundNumber.compareTo(b.roundNumber);
      if (r != 0) return r;
      final si = a.sortIndex.compareTo(b.sortIndex);
      if (si != 0) return si;
      return a.id.compareTo(b.id);
    });

    final lines = <String>[];
    for (final m in sorted) {
      final homeName = (_teamNames[m.homeTeamId] ?? l10n.tr('fixtures_tbd')).trim();
      final awayName = (_teamNames[m.awayTeamId] ?? l10n.tr('fixtures_tbd')).trim();
      lines.add('$homeName vs $awayName');
    }

    // Keep it clean: just the fixtures list.
    return lines.join('\n');
  }

  Future<void> _shareSelectedFixturesToLeagueChat() async {
    if (!_canAdminSelectFixtures) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) context.go('/login');
      return;
    }

    final selectedIds = _selectedFixtureIds.value;
    if (selectedIds.isEmpty) return;
    if (_isSharingFixtures) return;

    setState(() => _isSharingFixtures = true);
    try {
      await ConnectivityService.instance.requireOnline(timeout: const Duration(seconds: 4));

      final selectedMatches = _allMatches.where((m) => selectedIds.contains(m.id)).toList();
      if (selectedMatches.isEmpty) {
        _snack('No fixtures selected');
        _clearSelection();
        return;
      }

      final identity = await _chatRepo.resolveSenderIdentity(
        uid: user.uid,
        fallbackName: _fallbackSenderName(user),
        fallbackPhoto: _fallbackSenderPhoto(user),
      );

      final msg = _shareFixturesMessage(selectedMatches);

      await _chatRepo.sendLeagueMessage(
        leagueId: widget.leagueId,
        senderId: user.uid,
        senderName: identity.name,
        senderPhoto: identity.photo,
        type: ChatMessageType.text,
        text: msg,
      );

      _snack('Shared to league chat');
      _clearSelection();
    } catch (e) {
      _snack(UserFriendlyError.toMessage(e is Object ? e : Exception('unknown')));
    } finally {
      if (mounted) setState(() => _isSharingFixtures = false);
    }
  }

  PreferredSizeWidget _buildAppBar() {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;

    return PreferredSize(
      preferredSize: const Size.fromHeight(kToolbarHeight),
      child: ValueListenableBuilder<Set<String>>(
        valueListenable: _selectedFixtureIds,
        builder: (context, selected, _) {
          final selecting = selected.isNotEmpty;

          if (!selecting) {
            return AppBar(
              title: Text(l10n.tr('fixtures_appbar_title')),
              elevation: 0,
              backgroundColor: Colors.transparent,
              actions: [
                IconButton(
                  tooltip: l10n.tr('common_refresh'),
                  onPressed: _isLoading ? null : _loadInitialData,
                  icon: const Icon(Icons.refresh),
                ),
                if (_format == LeagueFormat.uclSwiss && _isOrganizer)
                  IconButton(
                    onPressed: _isGeneratingNextRound ? null : _generateNextSwissRound,
                    tooltip: l10n.tr('fixtures_generate_next_swiss_round_tooltip'),
                    icon: _isGeneratingNextRound
                        ? SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: cs.primary),
                          )
                        : Icon(Icons.auto_mode, color: cs.primary),
                  ),
              ],
            );
          }

          return AppBar(
            leading: IconButton(
              tooltip: 'Cancel',
              onPressed: _clearSelection,
              icon: const Icon(Icons.close_rounded),
            ),
            title: Text('${selected.length} selected'),
            elevation: 0,
            backgroundColor: Colors.transparent,
            actions: [
              IconButton(
                tooltip: 'Share to league chat',
                onPressed: (!_canAdminSelectFixtures || _isSharingFixtures)
                    ? null
                    : _shareSelectedFixturesToLeagueChat,
                icon: _isSharingFixtures
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: cs.primary),
                      )
                    : const Icon(Icons.share_outlined),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    _selectedFixtureIds.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final width = MediaQuery.of(context).size.width;
    final isTablet = width > 700;

    return WillPopScope(
      onWillPop: () async {
        if (_isSelectionMode) {
          _clearSelection();
          return false;
        }
        return true;
      },
      child: GlassScaffold(
        appBar: _buildAppBar(),
        body: SafeArea(
          child: _isLoading
              ? Center(child: CircularProgressIndicator(color: cs.primary))
              : (_loadError != null
                  ? _buildLoadErrorState(_loadError!)
                  : Center(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: isTablet ? 800 : 600),
                        child: RefreshIndicator(
                          onRefresh: _loadInitialData,
                          color: cs.primary,
                          child: Column(
                            children: [
                              if (_format == LeagueFormat.uclGroup && _groups.isNotEmpty) _buildGroupSelector(),
                              if (_totalRounds > 0) _buildRoundSelector(_totalRounds),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16),
                                child: SectionHeader(context.l10n.tr('fixtures_section_title')),
                              ),
                              Expanded(child: _buildMatchesList()),
                            ],
                          ),
                        ),
                      ),
                    )),
        ),
      ),
    );
  }

  Widget _buildLoadErrorState(String msg) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Glass(
            borderRadius: 24,
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.cloud_off_rounded, color: cs.primary, size: 44),
                  const SizedBox(height: 10),
                  Text(
                    'Couldn’t load fixtures',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: cs.onSurface,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    msg,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: cs.onSurface.withOpacity(0.70),
                      fontWeight: FontWeight.w600,
                      height: 1.35,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => context.pop(),
                          child: const Text('Back'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton(
                          onPressed: _loadInitialData,
                          child: const Text('Retry'),
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
    );
  }

  Widget _buildGroupSelector() {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;

    final unselectedBg = cs.onBackground.withOpacity(0.06);
    final unselectedBorder = cs.onBackground.withOpacity(0.14);
    final unselectedText = cs.onBackground.withOpacity(0.78);

    final bool allSelected = _selectedGroup == null;

    return Container(
      height: 44,
      margin: const EdgeInsets.only(top: 12, bottom: 4),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          GestureDetector(
            onTap: () => _setGroup(null),
            child: Container(
              margin: const EdgeInsetsDirectional.only(end: 10),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: allSelected ? cs.primary : unselectedBg,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: allSelected ? cs.primary : unselectedBorder),
              ),
              alignment: Alignment.center,
              child: Text(
                l10n.tr('admin_score_all_groups'),
                style: TextStyle(
                  color: allSelected ? cs.onPrimary : unselectedText,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
          ),
          for (final group in _groups)
            Builder(
              builder: (context) {
                final isSelected = _selectedGroup == group;
                return GestureDetector(
                  onTap: () => _setGroup(group),
                  child: Container(
                    margin: const EdgeInsetsDirectional.only(end: 10),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: isSelected ? cs.primary : unselectedBg,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: isSelected ? cs.primary : unselectedBorder),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      _groupDisplayName(l10n, group),
                      style: TextStyle(
                        color: isSelected ? cs.onPrimary : unselectedText,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildRoundSelector(int totalRounds) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;

    final unselectedBg = cs.onBackground.withOpacity(0.06);
    final unselectedBorder = cs.onBackground.withOpacity(0.14);
    final unselectedText = cs.onBackground.withOpacity(0.78);

    if (totalRounds > 0 && _selectedRound > totalRounds) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _setRound(totalRounds);
      });
    }

    return Container(
      height: 50,
      margin: const EdgeInsets.symmetric(vertical: 12),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: totalRounds,
        itemBuilder: (context, i) {
          final round = i + 1;
          final isSelected = _selectedRound == round;

          return GestureDetector(
            onTap: () => _setRound(round),
            child: Container(
              margin: const EdgeInsetsDirectional.only(end: 12),
              padding: const EdgeInsets.symmetric(horizontal: 20),
              decoration: BoxDecoration(
                color: isSelected ? cs.primary : unselectedBg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: isSelected ? cs.primary : unselectedBorder),
              ),
              alignment: Alignment.center,
              child: Text(
                '${l10n.tr('admin_score_round_prefix')}$round',
                style: TextStyle(
                  color: isSelected ? cs.onPrimary : unselectedText,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildMatchesList() {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;

    final matches = _matchesForSelectedRound();

    if (matches.isEmpty) {
      return Center(
        child: Text(
          l10n.tr('fixtures_no_matches_generated_yet'),
          style: TextStyle(color: cs.onBackground.withOpacity(0.70), fontWeight: FontWeight.w600),
          textAlign: TextAlign.center,
        ),
      );
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ids = <String>[
        for (final m in matches) m.homeTeamId,
        for (final m in matches) m.awayTeamId,
      ];
      _ensureUserImagesForTeamIds(ids);
    });

    return ValueListenableBuilder<Set<String>>(
      valueListenable: _selectedFixtureIds,
      builder: (context, selected, _) {
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: matches.length,
          itemBuilder: (context, index) {
            final m = matches[index];
            final isSelected = selected.contains(m.id);
            return _buildMatchCard(m, selected: isSelected);
          },
        );
      },
    );
  }

  Widget _buildMatchCard(FixtureMatch match, {required bool selected}) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final homeName = _teamNames[match.homeTeamId] ?? l10n.tr('fixtures_tbd');
    final awayName = _teamNames[match.awayTeamId] ?? l10n.tr('fixtures_tbd');
    final groupLabel = match.groupId?.trim().isNotEmpty == true ? match.groupId!.trim() : null;

    final homeUrl = (_teamImageUrls[match.homeTeamId] ?? '').trim();
    final awayUrl = (_teamImageUrls[match.awayTeamId] ?? '').trim();

    final isFinished = match.status == MatchStatus.completed || match.status == MatchStatus.played;
    final hasScore = match.homeScore != null && match.awayScore != null;

    final highlightBorder = selected ? cs.primary.withOpacity(0.95) : cs.onSurface.withOpacity(0.0);
    final highlightBg = selected ? cs.primary.withOpacity(0.08) : Colors.transparent;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _handleFixtureTap(match),
        onLongPress: _canAdminSelectFixtures ? () => _handleFixtureLongPress(match) : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            color: highlightBg,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: highlightBorder, width: 2),
          ),
          child: Stack(
            children: [
              Glass(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_format == LeagueFormat.uclGroup && groupLabel != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: Text(
                            _groupDisplayName(l10n, groupLabel),
                            style: TextStyle(
                              color: cs.onSurface.withOpacity(0.55),
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    Row(
                      children: [
                        Expanded(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Expanded(
                                child: Text(
                                  homeName,
                                  textAlign: TextAlign.end,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: cs.onSurface,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 8),
                              _TeamThumb(url: homeUrl),
                            ],
                          ),
                        ),
                        SizedBox(
                          width: 88,
                          child: Center(
                            child: (isFinished && hasScore)
                                ? Text(
                                    '${match.homeScore} - ${match.awayScore}',
                                    style: theme.textTheme.titleMedium?.copyWith(
                                      color: cs.primary,
                                      fontWeight: FontWeight.w900,
                                      fontSize: 18,
                                    ),
                                  )
                                : Text(
                                    l10n.tr('league_details_vs'),
                                    style: theme.textTheme.labelLarge?.copyWith(
                                      color: cs.onSurface.withOpacity(0.30),
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                          ),
                        ),
                        Expanded(
                          child: Row(
                            children: [
                              _TeamThumb(url: awayUrl),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  awayName,
                                  textAlign: TextAlign.start,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: cs.onSurface,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (selected)
                PositionedDirectional(
                  top: 10,
                  end: 10,
                  child: Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: cs.primary,
                      shape: BoxShape.circle,
                      border: Border.all(color: cs.primary.withOpacity(0.30)),
                    ),
                    child: Icon(Icons.check, size: 14, color: cs.onPrimary),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TeamThumb extends StatelessWidget {
  const _TeamThumb({
    required this.url,
  });

  final String url;

  bool _looksLikeHttpUrl(String s) {
    final u = s.trim().toLowerCase();
    return u.startsWith('https://') || u.startsWith('http://');
  }

  String _cloudinaryOptimizedUrl(String url, {int width = 64, int height = 64}) {
    final u = url.trim();
    if (u.isEmpty) return u;

    final isCloudinary = u.contains('res.cloudinary.com') && u.contains('/image/upload/');
    if (!isCloudinary) return u;

    final marker = '/image/upload/';
    final idx = u.indexOf(marker);
    if (idx < 0) return u;

    final prefix = u.substring(0, idx + marker.length);
    final suffix = u.substring(idx + marker.length);

    final transforms = 'f_auto,q_auto,w_$width,h_$height,c_fill,g_auto';

    final parts = suffix.split('/');
    if (parts.isEmpty) return '$prefix$transforms/$suffix';

    final first = parts.first;
    final isVersionOnly = first.startsWith('v') && int.tryParse(first.substring(1)) != null;

    if (!isVersionOnly) {
      if (first.contains('f_auto') || first.contains('q_auto')) return u;
      parts[0] = 'f_auto,q_auto,$first';
      return prefix + parts.join('/');
    }

    return '$prefix$transforms/$suffix';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final raw = url.trim();
    final has = raw.isNotEmpty && _looksLikeHttpUrl(raw);
    final d = has ? _cloudinaryOptimizedUrl(raw, width: 64, height: 64) : '';

    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        color: cs.onSurface.withOpacity(0.06),
        shape: BoxShape.circle,
        border: Border.all(color: cs.onSurface.withOpacity(0.14)),
      ),
      child: ClipOval(
        child: has
            ? Image.network(
                d,
                fit: BoxFit.cover,
                gaplessPlayback: true,
                filterQuality: FilterQuality.low,
                cacheWidth: 64,
                cacheHeight: 64,
                errorBuilder: (_, __, ___) =>
                    Icon(Icons.emoji_events_outlined, size: 14, color: cs.onSurface.withOpacity(0.55)),
                loadingBuilder: (context, child, event) {
                  if (event == null) return child;
                  return Icon(Icons.emoji_events_outlined, size: 14, color: cs.onSurface.withOpacity(0.55));
                },
              )
            : Icon(Icons.emoji_events_outlined, size: 14, color: cs.onSurface.withOpacity(0.55)),
      ),
    );
  }
}
