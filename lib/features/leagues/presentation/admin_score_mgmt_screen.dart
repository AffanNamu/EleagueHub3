import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/user_friendly_error.dart';
import '../../../core/locale/app_localizations.dart';
import '../../../core/persistence/prefs_service.dart';
import '../../../core/widgets/glass.dart';
import '../../../core/widgets/glass_scaffold.dart';
import '../../../core/widgets/section_header.dart';
import '../data/leagues_repository_local.dart';
import '../domain/algorithms/swiss_pairing.dart';
import '../logic/fixture_generator.dart';
import '../models/enums.dart';
import '../models/fixture_match.dart';
import '../models/league.dart';
import '../models/league_format.dart';
import '../models/team.dart';

class AdminScoreMgmtScreen extends ConsumerStatefulWidget {
  final String leagueId;
  const AdminScoreMgmtScreen({super.key, required this.leagueId});
  @override
  ConsumerState<AdminScoreMgmtScreen> createState() => _AdminScoreMgmtScreenState();
}

class _AdminScoreMgmtScreenState extends ConsumerState<AdminScoreMgmtScreen> {
  late LocalLeaguesRepository _repo;

  League? _league;
  List<Team> _teams = [];
  List<FixtureMatch> _matches = [];
  Map<String, String> _teamNames = {};
  bool _isLoading = true;
  String? _loadError;

  LeagueFormat _format = LeagueFormat.classic;
  List<String> _groups = [];

  /// null = "All groups" when format == uclGroup
  String? _selectedGroup;
  int _selectedRound = 1;

  bool _isGenerating = false;
  final Set<String> _savingMatchIds = <String>{};

  // teamId -> imageUrl (PRIMARY: users/{uid} profile image for UID-based teams)
  Map<String, String> _teamImageUrls = {};

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final Set<String> _requestedUserImageIds = <String>{};

  Color _baseToastBg(ThemeData theme) {
    // Premium: light mode should NOT use a dark toast background.
    if (theme.brightness == Brightness.dark) return const Color(0xFF101522);
    return const Color(0xFFF8FBFF);
  }

  void _toast(String msg, {Color? bg, Color? fg}) {
    if (!mounted) return;

    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final resolvedBg = bg ?? _baseToastBg(theme);
    final resolvedFg = fg ??
        (theme.brightness == Brightness.dark
            ? Colors.white
            : cs.onSurface.withOpacity(0.92));

    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(12),
        backgroundColor: resolvedBg,
        content: Text(
          msg,
          style: TextStyle(color: resolvedFg, fontWeight: FontWeight.w600),
        ),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _toastOk(String msg) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final baseBg = _baseToastBg(theme);
    final accent = cs.primary;

    _toast(
      msg,
      bg: Color.alphaBlend(accent.withOpacity(0.16), baseBg),
      fg: accent,
    );
  }

  void _toastWarn(String msg) {
    const warn = Color(0xFFF59E0B);
    final theme = Theme.of(context);
    final baseBg = _baseToastBg(theme);
    _toast(msg, bg: Color.alphaBlend(warn.withOpacity(0.16), baseBg), fg: warn);
  }

  void _toastErr(String msg) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final baseBg = _baseToastBg(theme);
    _toast(msg, bg: Color.alphaBlend(cs.error.withOpacity(0.14), baseBg), fg: cs.error);
  }

  @override
  void initState() {
    super.initState();
    _repo = LocalLeaguesRepository(ref.read(prefsServiceProvider));
    _loadData();
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

    const chunkSize = 10;
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
        // Requirement: user profile image is authoritative; overwrite is OK.
        _teamImageUrls = {..._teamImageUrls, ...userImages};
      });
    } catch (_) {
      // best-effort
    }
  }

  Map<String, String> _mergePreferExisting(Map<String, String> base, Map<String, String> incoming) {
    if (incoming.isEmpty) return base;
    final out = <String, String>{...base};
    incoming.forEach((k, v) {
      final key = k.trim();
      final val = v.trim();
      if (key.isEmpty || val.isEmpty) return;

      if ((out[key] ?? '').trim().isNotEmpty) return; // keep existing
      out[key] = val;
    });
    return out;
  }

  String _bestEffortUrlFromTeam(Team t) => t.teamImageUrl.trim();

  String _bestEffortUrlFromTeamDocMap(Map<String, dynamic> data) {
    final teamImageUrl = (data['teamImageUrl'] as String?)?.trim() ?? '';
    if (teamImageUrl.isNotEmpty) return teamImageUrl;

    final logoUrl = (data['logoUrl'] as String?)?.trim() ?? '';
    if (logoUrl.isNotEmpty) return logoUrl;

    final imageUrl = (data['imageUrl'] as String?)?.trim() ?? '';
    if (imageUrl.isNotEmpty) return imageUrl;

    return '';
  }

  Future<void> _refreshTeamImagesBestEffort({
    required List<Team> teams,
  }) async {
    // PRIMARY: from Team objects (already hydrated by LocalLeaguesRepository.getTeams()).
    final local = <String, String>{};
    for (final t in teams) {
      final url = _bestEffortUrlFromTeam(t);
      if (url.isNotEmpty) local[t.id] = url;
    }

    if (local.isNotEmpty && mounted) {
      setState(() {
        // Primary wins; overwrite is OK (user image authoritative).
        _teamImageUrls = {..._teamImageUrls, ...local};
      });
    }

    // SECONDARY: Firestore teams collection (fill missing only; don't override)
    try {
      final snap = await _firestore
          .collection('leagues')
          .doc(widget.leagueId)
          .collection('teams')
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 6));

      final remote = <String, String>{};
      for (final d in snap.docs) {
        final data = d.data();
        final id = (data['id'] is String && (data['id'] as String).trim().isNotEmpty) ? (data['id'] as String).trim() : d.id;
        final url = _bestEffortUrlFromTeamDocMap(data);
        if (id.trim().isNotEmpty && url.isNotEmpty) remote[id] = url;
      }

      if (!mounted) return;
      if (remote.isEmpty) return;

      setState(() {
        _teamImageUrls = _mergePreferExisting(_teamImageUrls, remote);
      });
    } catch (_) {
      // Best-effort only.
    }

    // Ensure user images exist for any UID-based team IDs (authoritative)
    final ids = teams.map((t) => t.id).toList();
    unawaited(_ensureUserImagesForTeamIds(ids));
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _loadError = null;
    });

    try {
      final leagueFuture = _repo.getLeagueById(widget.leagueId);
      final matchesFuture = _repo.getMatches(widget.leagueId);
      final teamsFuture = _repo.getTeams(widget.leagueId);

      final results = await Future.wait([leagueFuture, matchesFuture, teamsFuture]).timeout(const Duration(seconds: 30));

      final league = results[0] as League?;
      final matches = results[1] as List<FixtureMatch>;
      final teams = results[2] as List<Team>;

      final l10n = context.l10n;
      if (league == null) {
        if (!mounted) return;
        setState(() {
          _league = null;
          _teams = const [];
          _matches = const [];
          _teamNames = const {};
          _teamImageUrls = const {};
          _format = LeagueFormat.classic;
          _groups = const [];
          _selectedGroup = null;
          _selectedRound = 1;
          _loadError = l10n.tr('fixtures_league_not_found');
          _isLoading = false;
        });
        return;
      }

      final format = league.format;

      // Collect groups (only relevant for UCL Group) from matches.
      List<String> groups = [];
      if (format == LeagueFormat.uclGroup) {
        groups = matches
            .map((m) => m.groupId)
            .whereType<String>()
            .map((g) => g.trim())
            .where((g) => g.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
      }

      // Sort: pending first, finished last; then round/sortIndex
      matches.sort((a, b) {
        final aFinished = a.status == MatchStatus.completed || a.status == MatchStatus.played;
        final bFinished = b.status == MatchStatus.completed || b.status == MatchStatus.played;

        if (aFinished != bFinished) return aFinished ? 1 : -1;

        final rr = a.roundNumber.compareTo(b.roundNumber);
        if (rr != 0) return rr;

        final ss = a.sortIndex.compareTo(b.sortIndex);
        if (ss != 0) return ss;

        return a.id.compareTo(b.id);
      });

      // Preserve selected group if still valid, else reset to All.
      String? selectedGroup = _selectedGroup;
      if (format != LeagueFormat.uclGroup) {
        selectedGroup = null;
      } else if (selectedGroup != null && !groups.contains(selectedGroup)) {
        selectedGroup = null;
      }

      // Compute selected round given current data
      Iterable<FixtureMatch> forRounds = matches;
      if (format == LeagueFormat.uclGroup && selectedGroup != null) {
        forRounds = forRounds.where((m) => m.groupId == selectedGroup);
      }
      final roundSet = forRounds.map((m) => m.roundNumber).toSet();
      int selectedRound = _selectedRound;
      if (roundSet.isEmpty) {
        selectedRound = 1;
      } else if (!roundSet.contains(selectedRound)) {
        final sorted = roundSet.toList()..sort();
        selectedRound = sorted.first;
      }

      // Build primary image map from hydrated Team objects
      final primaryImages = <String, String>{};
      for (final t in teams) {
        final url = t.teamImageUrl.trim();
        if (url.isNotEmpty) primaryImages[t.id] = url;
      }

      if (!mounted) return;
      setState(() {
        _league = league;
        _teams = teams;
        _format = format;
        _groups = groups;
        _selectedGroup = selectedGroup;
        _matches = matches;
        _teamNames = {for (final t in teams) t.id: t.name};
        _teamImageUrls = primaryImages;
        _selectedRound = selectedRound;
        _isLoading = false;
      });

      unawaited(_refreshTeamImagesBestEffort(teams: teams));

      // Ensure user images for match ids (in case a team doc is missing)
      final matchIds = <String>[
        for (final m in matches) m.homeTeamId,
        for (final m in matches) m.awayTeamId,
      ];
      unawaited(_ensureUserImagesForTeamIds(matchIds));

      // Production correctness:
      // Ensure team aggregate fields are backfilled for older leagues so:
      // - basePoints is correct for admin point adjustments
      // - finalPoints invariant holds for secured team writes
      // Best-effort; if it fails, score editing still works but adjustments might be blocked by rules.
      unawaited(_repo.ensureTeamAggregatesBackfilled(widget.leagueId));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = UserFriendlyError.toMessage(e);
        _isLoading = false;
      });
    }
  }

  Future<void> _updateScore(
    FixtureMatch match,
    int hScore,
    int aScore,
  ) async {
    final l10n = context.l10n;

    if (_savingMatchIds.contains(match.id)) return;
    setState(() => _savingMatchIds.add(match.id));

    try {
      // Production-ready write:
      // - Updates match score AND team aggregates (basePoints/GD/GF/finalPoints) in a single transaction.
      // - This keeps admin point adjustments correct because they rely on basePoints.
      await _repo
          .updateMatchScoreAndUpdateTeamAggregates(
            leagueId: widget.leagueId,
            matchId: match.id,
            homeScore: hScore,
            awayScore: aScore,
          )
          .timeout(const Duration(seconds: 25));

      if (!mounted) return;
      _toastOk(l10n.tr('admin_score_toast_score_updated'));
      await _loadData();
    } catch (e) {
      if (!mounted) return;
      _toastErr(UserFriendlyError.toMessage(e));
    } finally {
      if (!mounted) return;
      setState(() => _savingMatchIds.remove(match.id));
    }
  }

  bool get _hasAnyMatches => _matches.isNotEmpty;
  bool get _hasGroupFixtures => _matches.any((m) => (m.groupId ?? '').trim().isNotEmpty);
  bool get _isSwissValidTeamCount => _teams.length == 18 || _teams.length == 36;
  bool get _isGroupValidTeamCount => _teams.length == 16 || _teams.length == 32;

  bool _groupsAssignedAndFull() {
    if (!_isGroupValidTeamCount) return false;
    // UCL group: groups of 4
    final byGroup = <String, int>{};
    for (final t in _teams) {
      final gid = (t.groupId ?? '').trim();
      if (gid.isEmpty) return false;
      byGroup[gid] = (byGroup[gid] ?? 0) + 1;
    }
    final expectedGroups = _teams.length ~/ 4;
    if (byGroup.length != expectedGroups) return false;
    for (final c in byGroup.values) {
      if (c != 4) return false;
    }
    return true;
  }

  Future<void> _generateClassicFixtures() async {
    final l10n = context.l10n;

    if (_isGenerating) return;
    if (_league == null) return;
    if (_teams.length < 2) {
      _toastErr(l10n.tr('admin_score_not_enough_teams'));
      return;
    }
    if (_hasAnyMatches) {
      _toastWarn(l10n.tr('admin_score_fixtures_already_exist'));
      return;
    }

    setState(() => _isGenerating = true);
    try {
      final fixtures = FixtureGenerator.generateClassicLeagueFixtures(
        leagueId: widget.leagueId,
        teams: _teams,
        doubleRoundRobin: _league!.settings.doubleRoundRobin,
      );

      if (fixtures.isEmpty) {
        _toastErr(l10n.tr('admin_score_failed_generate_fixtures'));
        return;
      }

      await _repo.saveMatches(widget.leagueId, fixtures).timeout(const Duration(seconds: 25));
      _toastOk(
        '${l10n.tr('admin_score_fixtures_generated_prefix')}${fixtures.length}${l10n.tr('admin_score_fixtures_generated_suffix')}',
      );
      await _loadData();
    } catch (e) {
      _toastErr(UserFriendlyError.toMessage(e));
    } finally {
      if (mounted) setState(() => _isGenerating = false);
    }
  }

  Future<void> _generateGroupFixtures() async {
    final l10n = context.l10n;

    if (_isGenerating) return;
    if (_league == null) return;
    if (!_isGroupValidTeamCount) {
      _toastErr('${l10n.tr('admin_score_group_team_count_error_prefix')}${_teams.length}.');
      return;
    }
    if (!_groupsAssignedAndFull()) {
      _toastWarn(l10n.tr('admin_score_complete_group_draw_first'));
      return;
    }
    if (_hasGroupFixtures) {
      _toastWarn(l10n.tr('admin_score_group_fixtures_already_exist'));
      return;
    }

    setState(() => _isGenerating = true);
    try {
      final fixtures = FixtureGenerator.generateUclGroupStage(
        leagueId: widget.leagueId,
        teams: _teams,
        doubleRoundRobin: _league!.settings.doubleRoundRobin,
        groupSize: 4,
      );

      if (fixtures.isEmpty) {
        _toastErr(l10n.tr('admin_score_failed_generate_group_fixtures'));
        return;
      }

      await _repo.saveMatches(widget.leagueId, fixtures).timeout(const Duration(seconds: 25));
      _toastOk(
        '${l10n.tr('admin_score_group_fixtures_generated_prefix')}${fixtures.length}${l10n.tr('admin_score_fixtures_generated_suffix')}',
      );
      await _loadData();
    } catch (e) {
      _toastErr(UserFriendlyError.toMessage(e));
    } finally {
      if (mounted) setState(() => _isGenerating = false);
    }
  }

  Future<void> _generateNextSwissRound() async {
    final l10n = context.l10n;

    if (_isGenerating) return;
    if (_league == null) return;
    if (!_isSwissValidTeamCount) {
      _toastErr('${l10n.tr('admin_score_swiss_team_count_error_prefix')}${_teams.length}.');
      return;
    }
    if (_teams.length.isOdd) {
      _toastErr(l10n.tr('admin_score_swiss_even_team_count_required'));
      return;
    }

    setState(() => _isGenerating = true);
    try {
      final maxRounds = _league!.settings.swissRounds;

      final existing = await _repo.getMatches(widget.leagueId).timeout(const Duration(seconds: 25));
      int currentMaxRound = 0;
      if (existing.isNotEmpty) {
        currentMaxRound = existing.map((m) => m.roundNumber).reduce((a, b) => a > b ? a : b);
      }

      // Require completion of current round before generating next
      if (currentMaxRound > 0) {
        final currentRoundMatches = existing.where((m) => m.roundNumber == currentMaxRound).toList();
        final anyUnplayed = currentRoundMatches.any((m) => !m.isPlayed);
        if (anyUnplayed) {
          _toastWarn(
            '${l10n.tr('admin_score_complete_round_prefix')}$currentMaxRound${l10n.tr('admin_score_complete_round_suffix')}',
          );
          return;
        }
      }

      if (currentMaxRound >= maxRounds) {
        _toastWarn(
          '${l10n.tr('admin_score_all_swiss_rounds_generated_prefix')}$maxRounds${l10n.tr('admin_score_all_swiss_rounds_generated_suffix')}',
        );
        return;
      }

      final nextRound = currentMaxRound == 0 ? 1 : currentMaxRound + 1;

      // Prevent duplicates
      final alreadyExists = existing.any((m) => m.roundNumber == nextRound);
      if (alreadyExists) {
        _toastWarn(
          '${l10n.tr('admin_score_round_already_exists_prefix')}$nextRound${l10n.tr('admin_score_round_already_exists_suffix')}',
        );
        return;
      }

      final newFixtures = (nextRound == 1)
          ? SwissPairingEngine.generateInitialRound(
              leagueId: widget.leagueId,
              teams: _teams,
              roundNumber: nextRound,
            )
          : SwissPairingEngine.generateNextRound(
              leagueId: widget.leagueId,
              teams: _teams,
              existingMatches: existing,
              nextRoundNumber: nextRound,
            );

      if (newFixtures.isEmpty) {
        _toastErr(l10n.tr('admin_score_no_swiss_pairings_generated'));
        return;
      }

      await _repo.saveMatches(widget.leagueId, newFixtures).timeout(const Duration(seconds: 25));
      _toastOk(
        '${l10n.tr('admin_score_swiss_round_generated_prefix')}$nextRound'
        '${l10n.tr('admin_score_swiss_round_generated_mid')}${newFixtures.length}'
        '${l10n.tr('admin_score_fixtures_generated_suffix')}',
      );
      await _loadData();
    } catch (e) {
      _toastErr(UserFriendlyError.toMessage(e));
    } finally {
      if (mounted) setState(() => _isGenerating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;

    final width = MediaQuery.of(context).size.width;
    final isTablet = width > 700;

    if (_isLoading) {
      return GlassScaffold(
        appBar: AppBar(
          title: Text(l10n.tr('admin_score_appbar_title')),
          backgroundColor: Colors.transparent,
          elevation: 0,
        ),
        body: SafeArea(
          child: Center(child: CircularProgressIndicator(color: cs.primary)),
        ),
      );
    }

    if (_loadError != null) {
      return GlassScaffold(
        appBar: AppBar(
          title: Text(l10n.tr('admin_score_appbar_title')),
          backgroundColor: Colors.transparent,
          elevation: 0,
        ),
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: isTablet ? 800 : 520),
                child: Glass(
                  borderRadius: 20,
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _loadError!,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: cs.error, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: _loadData,
                          icon: const Icon(Icons.refresh),
                          label: Text(l10n.tr('common_retry')),
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextButton(
                        onPressed: () => Navigator.maybePop(context),
                        child: Text(l10n.tr('common_back')),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    // Available rounds based on current selection
    List<int> availableRounds = [];
    {
      Iterable<FixtureMatch> forRounds = _matches;
      if (_format == LeagueFormat.uclGroup && _selectedGroup != null) {
        forRounds = forRounds.where((m) => m.groupId == _selectedGroup);
      }
      final roundSet = forRounds.map((m) => m.roundNumber).toSet();
      availableRounds = roundSet.toList()..sort();
    }

    // Apply group + round filters
    List<FixtureMatch> visibleMatches = _matches;
    if (_format == LeagueFormat.uclGroup && _selectedGroup != null) {
      visibleMatches = visibleMatches.where((m) => m.groupId == _selectedGroup).toList();
    }
    if (availableRounds.isNotEmpty) {
      visibleMatches = visibleMatches.where((m) => m.roundNumber == _selectedRound).toList();
    }

    // Ensure user images for visible matches (post-frame).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ids = <String>[
        for (final m in visibleMatches) m.homeTeamId,
        for (final m in visibleMatches) m.awayTeamId,
      ];
      // ignore: discarded_futures
      _ensureUserImagesForTeamIds(ids);
    });

    final showGenerateClassic = _format == LeagueFormat.classic && !_hasAnyMatches;
    final showGenerateGroup = _format == LeagueFormat.uclGroup && !_hasGroupFixtures;
    final showGenerateSwiss = _format == LeagueFormat.uclSwiss;

    return GlassScaffold(
      appBar: AppBar(
        title: Text(l10n.tr('admin_score_appbar_title')),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: l10n.tr('admin_knockout_reload_tooltip'),
            onPressed: _loadData,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: isTablet ? 1000 : 500),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: SectionHeader(l10n.tr('admin_score_section_title')),
                ),
                const SizedBox(height: 6),
                if (showGenerateClassic || showGenerateGroup || showGenerateSwiss)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      children: [
                        if (showGenerateClassic)
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: cs.primary,
                                side: BorderSide(color: cs.primary),
                              ),
                              onPressed: _isGenerating ? null : _generateClassicFixtures,
                              icon: _isGenerating
                                  ? SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: cs.primary),
                                    )
                                  : const Icon(Icons.auto_awesome),
                              label: Text(
                                l10n.tr('admin_score_generate_classic'),
                                style: const TextStyle(fontWeight: FontWeight.w900),
                              ),
                            ),
                          ),
                        if (showGenerateGroup)
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: cs.primary,
                                side: BorderSide(color: cs.primary),
                              ),
                              onPressed: _isGenerating ? null : _generateGroupFixtures,
                              icon: _isGenerating
                                  ? SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: cs.primary),
                                    )
                                  : const Icon(Icons.groups_2),
                              label: Text(
                                l10n.tr('admin_score_generate_group'),
                                style: const TextStyle(fontWeight: FontWeight.w900),
                              ),
                            ),
                          ),
                        if (showGenerateSwiss)
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: cs.primary,
                                side: BorderSide(color: cs.primary),
                              ),
                              onPressed: _isGenerating ? null : _generateNextSwissRound,
                              icon: _isGenerating
                                  ? SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: cs.primary),
                                    )
                                  : const Icon(Icons.auto_mode),
                              label: Text(
                                l10n.tr('admin_score_generate_next_swiss_round'),
                                style: const TextStyle(fontWeight: FontWeight.w900),
                              ),
                            ),
                          ),
                        const SizedBox(height: 6),
                      ],
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Text(
                    l10n.tr('admin_score_help_text'),
                    style: TextStyle(color: cs.onBackground.withOpacity(0.62), fontSize: 12),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 8),
                if (_format == LeagueFormat.uclGroup && _groups.isNotEmpty) _buildGroupSelector(),
                if (availableRounds.isNotEmpty) _buildRoundSelector(availableRounds),
                const SizedBox(height: 4),
                Expanded(
                  child: visibleMatches.isEmpty
                      ? Center(
                          child: Text(
                            l10n.tr('admin_score_no_matches_to_manage'),
                            style: TextStyle(color: cs.onBackground.withOpacity(0.70), fontWeight: FontWeight.w600),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: visibleMatches.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 12),
                          itemBuilder: (context, index) {
                            final match = visibleMatches[index];
                            final saving = _savingMatchIds.contains(match.id);

                            final homeUrl = (_teamImageUrls[match.homeTeamId] ?? '').trim();
                            final awayUrl = (_teamImageUrls[match.awayTeamId] ?? '').trim();

                            return _ScoreEntryTile(
                              key: ValueKey(match.id),
                              match: match,
                              homeName: _teamNames[match.homeTeamId] ?? l10n.tr('admin_score_home_fallback'),
                              awayName: _teamNames[match.awayTeamId] ?? l10n.tr('admin_score_away_fallback'),
                              homeImageUrl: homeUrl,
                              awayImageUrl: awayUrl,
                              saving: saving,
                              onSave: (h, a) => _updateScore(match, h, a),
                            );
                          },
                        ),
                ),
              ],
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
      height: 40,
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          GestureDetector(
            onTap: () {
              final roundSet = _matches.map((m) => m.roundNumber).toSet();
              int newRound = _selectedRound;
              if (roundSet.isEmpty) {
                newRound = 1;
              } else if (!roundSet.contains(newRound)) {
                final sorted = roundSet.toList()..sort();
                newRound = sorted.first;
              }

              setState(() {
                _selectedGroup = null;
                _selectedRound = newRound;
              });
            },
            child: Container(
              margin: const EdgeInsetsDirectional.only(end: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: allSelected ? cs.primary : unselectedBg,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: allSelected ? cs.primary : unselectedBorder,
                ),
              ),
              alignment: Alignment.center,
              child: Text(
                l10n.tr('admin_score_all_groups'),
                style: TextStyle(
                  color: allSelected ? cs.onPrimary : unselectedText,
                  fontWeight: FontWeight.bold,
                  fontSize: 11,
                ),
              ),
            ),
          ),
          for (final group in _groups)
            Builder(
              builder: (context) {
                final isSelected = _selectedGroup == group;
                return GestureDetector(
                  onTap: () {
                    final roundSet = _matches.where((m) => m.groupId == group).map((m) => m.roundNumber).toSet();
                    int newRound = _selectedRound;
                    if (roundSet.isEmpty) {
                      newRound = 1;
                    } else if (!roundSet.contains(newRound)) {
                      final sorted = roundSet.toList()..sort();
                      newRound = sorted.first;
                    }

                    setState(() {
                      _selectedGroup = group;
                      _selectedRound = newRound;
                    });
                  },
                  child: Container(
                    margin: const EdgeInsetsDirectional.only(end: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: isSelected ? cs.primary : unselectedBg,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: isSelected ? cs.primary : unselectedBorder,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      group,
                      style: TextStyle(
                        color: isSelected ? cs.onPrimary : unselectedText,
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
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

  Widget _buildRoundSelector(List<int> rounds) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;

    final unselectedBg = cs.onBackground.withOpacity(0.06);
    final unselectedBorder = cs.onBackground.withOpacity(0.14);
    final unselectedText = cs.onBackground.withOpacity(0.78);

    return Container(
      height: 46,
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: rounds.length,
        itemBuilder: (context, i) {
          final round = rounds[i];
          final isSelected = _selectedRound == round;
          return GestureDetector(
            onTap: () => setState(() => _selectedRound = round),
            child: Container(
              margin: const EdgeInsetsDirectional.only(end: 10),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
              decoration: BoxDecoration(
                color: isSelected ? cs.primary : unselectedBg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isSelected ? cs.primary : unselectedBorder,
                ),
              ),
              alignment: Alignment.center,
              child: Text(
                '${l10n.tr('admin_score_round_prefix')}$round',
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
    );
  }
}

class _ScoreEntryTile extends StatefulWidget {
  final FixtureMatch match;
  final String homeName;
  final String awayName;
  final String homeImageUrl;
  final String awayImageUrl;
  final bool saving;
  final Future<void> Function(int, int) onSave;

  const _ScoreEntryTile({
    super.key,
    required this.match,
    required this.homeName,
    required this.awayName,
    required this.homeImageUrl,
    required this.awayImageUrl,
    required this.saving,
    required this.onSave,
  });

  @override
  State<_ScoreEntryTile> createState() => _ScoreEntryTileState();
}

class _ScoreEntryTileState extends State<_ScoreEntryTile> {
  late int _homeScore;
  late int _awayScore;

  @override
  void initState() {
    super.initState();
    _homeScore = widget.match.homeScore ?? 0;
    _awayScore = widget.match.awayScore ?? 0;
  }

  @override
  void didUpdateWidget(covariant _ScoreEntryTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.match.id != widget.match.id ||
        oldWidget.match.homeScore != widget.match.homeScore ||
        oldWidget.match.awayScore != widget.match.awayScore) {
      _homeScore = widget.match.homeScore ?? 0;
      _awayScore = widget.match.awayScore ?? 0;
    }
  }

  bool get _isCompleted => widget.match.status == MatchStatus.completed || widget.match.status == MatchStatus.played;

  bool get _disabled => widget.saving;

  void _incHome() {
    if (_disabled) return;
    setState(() => _homeScore++);
  }

  void _decHome() {
    if (_disabled) return;
    setState(() {
      if (_homeScore > 0) _homeScore--;
    });
  }

  void _incAway() {
    if (_disabled) return;
    setState(() => _awayScore++);
  }

  void _decAway() {
    if (_disabled) return;
    setState(() {
      if (_awayScore > 0) _awayScore--;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final onSurface = cs.onSurface;
    final primary = cs.primary;

    final groupLabel = widget.match.groupId?.trim().isNotEmpty == true ? widget.match.groupId!.trim() : null;

    return Glass(
      padding: const EdgeInsets.all(18),
      child: Opacity(
        opacity: widget.saving ? 0.72 : 1,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (groupLabel != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    groupLabel,
                    style: TextStyle(
                      color: onSurface.withOpacity(0.55),
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
                    children: [
                      _TeamThumb(url: widget.homeImageUrl),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          widget.homeName,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    l10n.tr('league_details_vs'),
                    style: TextStyle(
                      color: onSurface.withOpacity(0.30),
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                Expanded(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Text(
                          widget.awayName,
                          textAlign: TextAlign.end,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      _TeamThumb(url: widget.awayImageUrl),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _isCompleted ? primary.withOpacity(0.14) : onSurface.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    _isCompleted ? l10n.tr('admin_knockout_status_completed') : l10n.tr('admin_knockout_status_pending'),
                    style: TextStyle(
                      color: _isCompleted ? primary : onSurface.withOpacity(0.55),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _scoreStepper(
                  value: _homeScore,
                  onInc: _incHome,
                  onDec: _decHome,
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Text(
                    ":",
                    style: TextStyle(
                      color: onSurface.withOpacity(0.35),
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                _scoreStepper(
                  value: _awayScore,
                  onInc: _incAway,
                  onDec: _decAway,
                ),
                const SizedBox(width: 24),
                IconButton.filled(
                  onPressed: _disabled
                      ? null
                      : () async {
                          FocusScope.of(context).unfocus();
                          await widget.onSave(_homeScore, _awayScore);
                        },
                  style: IconButton.styleFrom(
                    backgroundColor: primary.withOpacity(0.18),
                    foregroundColor: primary,
                  ),
                  icon: widget.saving
                      ? SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: primary,
                          ),
                        )
                      : const Icon(Icons.done_all, size: 24),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _scoreStepper({
    required int value,
    required VoidCallback onInc,
    required VoidCallback onDec,
  }) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final onSurface = cs.onSurface;

    return Container(
      decoration: BoxDecoration(
        color: onSurface.withOpacity(0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: onSurface.withOpacity(0.12)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _stepperButton(
            icon: Icons.remove,
            onPressed: value > 0 ? onDec : null,
            enabled: value > 0 && !widget.saving,
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 28,
            child: Text(
              '$value',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge?.copyWith(
                fontSize: 22,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 6),
          _stepperButton(
            icon: Icons.add,
            onPressed: widget.saving ? null : onInc,
            enabled: !widget.saving,
          ),
        ],
      ),
    );
  }

  Widget _stepperButton({
    required IconData icon,
    required VoidCallback? onPressed,
    required bool enabled,
  }) {
    final cs = Theme.of(context).colorScheme;
    final onSurface = cs.onSurface;
    final primary = cs.primary;

    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: enabled ? primary.withOpacity(0.10) : onSurface.withOpacity(0.04),
          shape: BoxShape.circle,
        ),
        child: Icon(
          icon,
          size: 18,
          color: enabled ? primary : onSurface.withOpacity(0.30),
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
                errorBuilder: (_, __, ___) => Icon(
                  Icons.emoji_events_outlined,
                  size: 14,
                  color: cs.onSurface.withOpacity(0.55),
                ),
                loadingBuilder: (context, child, event) {
                  if (event == null) return child;
                  return Icon(
                    Icons.emoji_events_outlined,
                    size: 14,
                    color: cs.onSurface.withOpacity(0.55),
                  );
                },
              )
            : Icon(
                Icons.emoji_events_outlined,
                size: 14,
                color: cs.onSurface.withOpacity(0.55),
              ),
      ),
    );
  }
}
