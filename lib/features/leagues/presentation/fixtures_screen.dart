import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;

import '../../../core/errors/user_friendly_error.dart';
import '../../../core/locale/app_localizations.dart';
import '../../../core/persistence/prefs_service.dart';
import '../../../core/services/connectivity_service.dart';
import '../../../core/theme/app_theme.dart';
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

enum _ShareTarget { leagueChat, globalChat }

class _FixturesScreenState extends ConsumerState<FixturesScreen>
    with WidgetsBindingObserver {
  int _selectedRound = 1;

  late LocalLeaguesRepository _repo;
  late PreferencesService _prefs;

  final ChatRepository _chatRepo = ChatRepository();

  Map<String, String> _teamNames = {};
  Map<String, String> _teamImageUrls = {};

  bool _isLoading = true;
  String? _loadError;

  LeagueFormat _format = LeagueFormat.classic;
  List<String> _groups = [];
  String? _selectedGroup;

  bool _isGeneratingNextRound = false;
  bool _isOrganizer = false;

  final ValueNotifier<Set<String>> _selectedFixtureIds =
      ValueNotifier<Set<String>>(<String>{});
  bool _isSharingFixtures = false;

  final GlobalKey _shareCardKey = GlobalKey();
  _ShareCardPayload? _sharePayload;

  String _leagueName = '';
  String _leagueLogoUrl = '';
  Uint8List? _leagueLogoBytes;

  List<FixtureMatch> _allMatches = const [];
  int _totalRounds = 0;

  static String _lastRoundKey(String leagueId) => 'ui_last_round_$leagueId';
  static String _lastGroupKey(String leagueId) => 'ui_last_group_$leagueId';

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final Set<String> _requestedUserImageIds = <String>{};

  static const String _superAdminUid = 'a0JDUelQW3TEyoXTm4ESuGi7ndq1';

  bool get _isSuperAdmin =>
      (FirebaseAuth.instance.currentUser?.uid.trim() ?? '') == _superAdminUid;

  bool get _canAdminSelectFixtures => _isOrganizer || _isSuperAdmin;

  bool get _isSelectionMode => _selectedFixtureIds.value.isNotEmpty;

  void _debugLog(String msg, [Object? err, StackTrace? st]) {
    assert(() {
      print('[FixturesShare] $msg');
      if (err != null) {
        print('  error: $err');
      }
      if (st != null) {
        print('  stack:\n$st');
      }
      return true;
    }());
  }

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
    _selectedGroup = (savedGroupRaw == null || savedGroupRaw.trim().isEmpty)
        ? null
        : savedGroupRaw.trim();

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
    _clearSelection();
    setState(() => _selectedRound = round);
    _persistRound(round);
  }

  void _setGroup(String? group) {
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

  Color _snackBg(ThemeData theme) {
    return theme.brightness == Brightness.dark
        ? const Color(0xFF101522)
        : const Color(0xF2FFFFFF);
  }

  Color _snackFg(ThemeData theme) {
    if (theme.brightness == Brightness.dark) return Colors.white;
    return theme.colorScheme.onSurface.withOpacity(0.92);
  }

  void _snack(String msg) {
    if (!mounted) return;

    final theme = Theme.of(context);

    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(12),
        backgroundColor: _snackBg(theme),
        content: Text(
          msg,
          style: TextStyle(
            color: _snackFg(theme),
            fontWeight: FontWeight.w700,
            height: 1.2,
          ),
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
    final clean = ids
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty && _looksLikeFirebaseUid(e))
        .toList(growable: false);
    if (clean.isEmpty) return const <String, String>{};

    final out = <String, String>{};

    const chunkSize = 10;
    for (var i = 0; i < clean.length; i += chunkSize) {
      final chunk = clean.sublist(
        i,
        (i + chunkSize > clean.length) ? clean.length : i + chunkSize,
      );

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
    } catch (_) {}
  }

  Map<String, String> _mergePreferExisting(
      Map<String, String> base, Map<String, String> incoming) {
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
        final id = (data['id'] is String &&
                (data['id'] as String).trim().isNotEmpty)
            ? (data['id'] as String).trim()
            : d.id;

        final candidate = (data['teamImageUrl'] as String?)?.trim() ?? '';
        if (id.isNotEmpty && candidate.isNotEmpty) out[id] = candidate;
      }

      if (!mounted) return;
      if (out.isEmpty) return;

      setState(() {
        _teamImageUrls = _mergePreferExisting(_teamImageUrls, out);
      });
    } catch (_) {}
  }

  String _bestLeagueLogoFromLeagueDoc(Map<String, dynamic> data) {
    final a = (data['logoUrl'] as String?)?.trim() ?? '';
    if (a.isNotEmpty) return a;
    final b = (data['imageUrl'] as String?)?.trim() ?? '';
    if (b.isNotEmpty) return b;
    final c = (data['bannerUrl'] as String?)?.trim() ?? '';
    if (c.isNotEmpty) return c;
    return '';
  }

  Future<Uint8List?> _fetchBytesBestEffort(String url) async {
    final u = url.trim();
    if (u.isEmpty) return null;

    final client = HttpClient()..connectionTimeout = const Duration(seconds: 7);
    try {
      final req = await client.getUrl(Uri.parse(u));
      req.headers.set('User-Agent', 'eSportyic');
      final res = await req.close().timeout(const Duration(seconds: 10));
      if (res.statusCode < 200 || res.statusCode >= 300) return null;

      final bytes = <int>[];
      await for (final chunk in res) {
        bytes.addAll(chunk);
        if (bytes.length > 3 * 1024 * 1024) break;
      }
      return Uint8List.fromList(bytes);
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _loadLeagueBrandingBestEffort({Object? leagueObject}) async {
    var name = _leagueName;
    var logoUrl = _leagueLogoUrl;

    try {
      final d = leagueObject as dynamic;
      final n = d?.name;
      if (n is String && n.trim().isNotEmpty) name = n.trim();
    } catch (_) {}

    try {
      final d = leagueObject as dynamic;
      final l = d?.logoUrl;
      if (l is String && l.trim().isNotEmpty) logoUrl = l.trim();
    } catch (_) {}

    try {
      final snap =
          await _firestore.collection('leagues').doc(widget.leagueId).get();
      final data = snap.data();
      if (data != null) {
        final n = (data['name'] as String?)?.trim() ?? '';
        if (n.isNotEmpty) name = n;

        final l = _bestLeagueLogoFromLeagueDoc(data);
        if (l.isNotEmpty) logoUrl = l;
      }
    } catch (_) {}

    if (!mounted) return;
    setState(() {
      _leagueName = name;
      _leagueLogoUrl = logoUrl;
    });

    if (_leagueLogoBytes == null && logoUrl.trim().isNotEmpty) {
      try {
        final b = await _fetchBytesBestEffort(logoUrl.trim());
        if (!mounted) return;
        if (b != null && b.isNotEmpty) {
          setState(() => _leagueLogoBytes = b);
        }
      } catch (_) {}
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

      await ConnectivityService.instance
          .requireOnline(timeout: const Duration(seconds: 4));

      final league = await _repo.getLeagueById(widget.leagueId)
          .timeout(const Duration(seconds: 20));
      unawaited(_loadLeagueBrandingBestEffort(leagueObject: league));

      final teams = await _repo.getTeams(widget.leagueId)
          .timeout(const Duration(seconds: 20));
      final allMatches = await _repo.getMatches(widget.leagueId)
          .timeout(const Duration(seconds: 25));

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
      if (totalRounds > 0 && roundToUse > totalRounds) {
        roundToUse = totalRounds;
      }
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

      final isOrganizer = membership?.role == LeagueRole.organizer ||
          (league?.organizerUid.trim() == authUid);

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
        _loadError = UserFriendlyError.toMessage(
          e is Object ? e : Exception('unknown'),
        );
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

      await ConnectivityService.instance
          .requireOnline(timeout: const Duration(seconds: 4));

      final league = await _repo.getLeagueById(widget.leagueId)
          .timeout(const Duration(seconds: 20));
      if (league == null) {
        _snack(l10n.tr('fixtures_league_not_found'));
        return;
      }

      final maxRounds = league.settings.swissRounds;

      final teams = await _repo.getTeams(widget.leagueId)
          .timeout(const Duration(seconds: 20));

      final n = teams.length;
      if (!(n == 18 || n == 36)) {
        _snack('${l10n.tr('fixtures_swiss_team_count_error_prefix')}$n.');
        return;
      }

      final existingMatches = await _repo.getMatches(widget.leagueId)
          .timeout(const Duration(seconds: 25));

      int currentMaxRound = 0;
      if (existingMatches.isNotEmpty) {
        currentMaxRound = existingMatches
            .map((m) => m.roundNumber)
            .reduce((a, b) => a > b ? a : b);
      }

      if (currentMaxRound > 0) {
        final currentRoundMatches = existingMatches
            .where((m) => m.roundNumber == currentMaxRound)
            .toList();
        final anyUnplayed = currentRoundMatches.any((m) => !m.isPlayed);
        if (anyUnplayed) {
          _snack(
            '${l10n.tr('admin_score_complete_round_prefix')}$currentMaxRound${l10n.tr('admin_score_complete_round_suffix')}',
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
            '${l10n.tr('admin_score_all_swiss_rounds_generated_prefix')}$maxRounds${l10n.tr('admin_score_all_swiss_rounds_generated_suffix')}',
          );
          return;
        }

        nextRound = currentMaxRound + 1;

        final alreadyExists =
            existingMatches.any((m) => m.roundNumber == nextRound);
        if (alreadyExists) {
          _snack(
            '${l10n.tr('admin_score_round_already_exists_prefix')}$nextRound${l10n.tr('admin_score_round_already_exists_suffix')}',
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

      await _repo.saveMatches(widget.leagueId, newFixtures)
          .timeout(const Duration(seconds: 25));

      if (!mounted) return;

      _setRound(nextRound);

      _snack(
        '${l10n.tr('fixtures_swiss_round_generated_prefix')}$nextRound${l10n.tr('fixtures_swiss_round_generated_suffix')}',
      );

      await _loadInitialData();
    } catch (e) {
      if (mounted) {
        _snack(
          UserFriendlyError.toMessage(
            e is Object ? e : Exception('unknown'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isGeneratingNextRound = false);
    }
  }

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

    final matchDetailsRoute =
        '/leagues/${widget.leagueId}/matches/${match.id}';

    final statusName = match.status.toString().toLowerCase();
    final isStreaming = statusName.contains('stream');

    if (isStreaming) {
      final streamRoute =
          '/leagues/${widget.leagueId}/matches/${match.id}/stream';
      try {
        await context.push(streamRoute);
        return;
      } catch (_) {}
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

  RenderRepaintBoundary? _shareBoundary() {
    final ctx = _shareCardKey.currentContext;
    final ro = ctx?.findRenderObject();
    if (ro is RenderRepaintBoundary) return ro;
    return null;
  }

  Future<void> _waitFrames(int frames) async {
    for (var i = 0; i < frames; i++) {
      await WidgetsBinding.instance.endOfFrame;
      await Future<void>.delayed(const Duration(milliseconds: 8));
    }
  }

  Future<Uint8List> _captureShareCardPngBytes() async {
    await _waitFrames(3);

    final boundary = _shareBoundary();
    if (boundary == null) throw StateError('Share card boundary missing.');

    final size = boundary.size;
    if (size.isEmpty) throw StateError('Share card has zero size.');

    final ratios = <double>[2.5, 2.0, 1.5, 1.25];
    Object? lastErr;

    for (final r in ratios) {
      try {
        final img = await boundary.toImage(pixelRatio: r);
        final bd = await img.toByteData(format: ui.ImageByteFormat.png);
        if (bd == null) throw StateError('PNG encoding failed.');
        return bd.buffer.asUint8List();
      } catch (e) {
        lastErr = e;
        _debugLog('toImage failed at pixelRatio=$r (retry lower)', e);
      }
    }

    throw StateError('Failed to capture share image. Last error: $lastErr');
  }

  Future<String> _writePngToTempFile(Uint8List bytes) async {
    final tmp = Directory.systemTemp.path;
    final fileName =
        'fixtures_share_${widget.leagueId}_${DateTime.now().millisecondsSinceEpoch}.png';
    final outPath = p.join(tmp, fileName);

    final f = File(outPath);
    await f.writeAsBytes(bytes, flush: true);
    return outPath;
  }

  Future<bool> _canShareToGlobalChat() async {
    if (_isSuperAdmin) return true;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;

    try {
      final snap =
          await _firestore.collection('globalChatRequests').doc(user.uid).get();
      final data = snap.data();
      final status = (data?['status'] as String? ?? '').trim().toLowerCase();
      return status == 'approved';
    } catch (_) {
      return false;
    }
  }

  Future<_ShareTarget?> _pickShareTarget() async {
    final allowGlobal = await _canShareToGlobalChat();

    if (!mounted) return null;

    if (!allowGlobal) return _ShareTarget.leagueChat;

    final theme = Theme.of(context);
    final brightness = theme.brightness;

    final picked = await showModalBottomSheet<_ShareTarget>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final t = Theme.of(ctx);

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 16),
            child: Glass(
              borderRadius: 20,
              fill: AppTheme.cardColor(brightness),
              borderColor: AppTheme.cardBorder(brightness),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 12),
                  Container(
                    width: 46,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppTheme.cardBorder(brightness),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Share to…',
                    style: TextStyle(
                      color: AppTheme.primaryText(brightness),
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 10),
                  ListTile(
                    leading: const Icon(
                      Icons.groups_2_rounded,
                      color: AppTheme.limeAccentDark,
                    ),
                    title: const Text('League Chat'),
                    subtitle: const Text('Share inside this league'),
                    onTap: () =>
                        Navigator.of(ctx).pop(_ShareTarget.leagueChat),
                  ),
                  ListTile(
                    leading: const Icon(
                      Icons.public_rounded,
                      color: AppTheme.limeAccentDark,
                    ),
                    title: const Text('Global Chat'),
                    subtitle: const Text('Share to global public chat'),
                    onTap: () =>
                        Navigator.of(ctx).pop(_ShareTarget.globalChat),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    return picked;
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

    final target = await _pickShareTarget();
    if (target == null) return;

    await _shareSelectedFixturesToChat(target);
  }

  Future<void> _shareSelectedFixturesToChat(_ShareTarget target) async {
    if (!_canAdminSelectFixtures) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) context.go('/login');
      return;
    }

    final selectedIds = _selectedFixtureIds.value;
    if (selectedIds.isEmpty) return;
    if (_isSharingFixtures) return;

    String step = 'prepare';
    setState(() => _isSharingFixtures = true);

    try {
      await ConnectivityService.instance
          .requireOnline(timeout: const Duration(seconds: 4));

      final selectedMatches =
          _allMatches.where((m) => selectedIds.contains(m.id)).toList();
      if (selectedMatches.isEmpty) {
        _snack('No fixtures selected');
        _clearSelection();
        return;
      }

      step = 'resolve identity';
      final identity = await _chatRepo.resolveSenderIdentity(
        uid: user.uid,
        fallbackName: _fallbackSenderName(user),
        fallbackPhoto: _fallbackSenderPhoto(user),
      );

      if (_leagueLogoBytes == null && _leagueLogoUrl.trim().isNotEmpty) {
        try {
          final b = await _fetchBytesBestEffort(_leagueLogoUrl.trim());
          if (b != null && b.isNotEmpty && mounted) {
            setState(() => _leagueLogoBytes = b);
          }
        } catch (_) {}
      }

      step = 'render card';
      if (mounted) {
        setState(() {
          _sharePayload = _ShareCardPayload(
            leagueId: widget.leagueId,
            leagueName:
                _leagueName.trim().isEmpty ? 'League' : _leagueName.trim(),
            leagueLogoBytes: _leagueLogoBytes,
            leagueFormat: _format,
            selectedGroup: _selectedGroup,
            matches: selectedMatches,
            teamNames: _teamNames,
          );
        });
      }

      step = 'capture card';
      final pngBytes = await _captureShareCardPngBytes();

      if (mounted) setState(() => _sharePayload = null);

      step = 'write temp';
      final tmpPath = await _writePngToTempFile(pngBytes);
      final f = File(tmpPath);
      if (!await f.exists()) {
        throw StateError('Generated image file not found.');
      }

      step = 'upload image';
      String url;

      if (target == _ShareTarget.globalChat) {
        url = await _chatRepo.uploadGlobalChatImage(
          file: PlatformFile(
            name: p.basename(tmpPath),
            path: tmpPath,
            size: await f.length(),
          ),
        );
      } else {
        url = await _chatRepo.uploadLeagueChatImage(
          leagueId: widget.leagueId,
          file: PlatformFile(
            name: p.basename(tmpPath),
            path: tmpPath,
            size: await f.length(),
          ),
        );
      }

      step = 'send message';
      if (target == _ShareTarget.globalChat) {
        await _chatRepo.sendGlobalMessage(
          senderId: user.uid,
          senderName: identity.name,
          senderPhoto: identity.photo,
          type: ChatMessageType.image,
          text: '',
          imageUrl: url,
        );
      } else {
        await _chatRepo.sendLeagueMessage(
          leagueId: widget.leagueId,
          senderId: user.uid,
          senderName: identity.name,
          senderPhoto: identity.photo,
          type: ChatMessageType.image,
          text: '',
          imageUrl: url,
        );
      }

      try {
        if (await f.exists()) await f.delete();
      } catch (_) {}

      _snack(
        target == _ShareTarget.globalChat
            ? 'Shared to global chat'
            : 'Shared to league chat',
      );
      _clearSelection();
    } catch (e, st) {
      _debugLog('Share failed at step="$step"', e, st);

      if (mounted && _sharePayload != null) {
        setState(() => _sharePayload = null);
      }

      _snack('Could not share fixtures ($step). Please try again.');
    } finally {
      if (mounted) setState(() => _isSharingFixtures = false);
    }
  }

  PreferredSizeWidget _buildAppBar() {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final brightness = theme.brightness;

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
                    onPressed: _isGeneratingNextRound
                        ? null
                        : _generateNextSwissRound,
                    tooltip: l10n
                        .tr('fixtures_generate_next_swiss_round_tooltip'),
                    icon: _isGeneratingNextRound
                        ? SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: cs.primary,
                            ),
                          )
                        : const Icon(
                            Icons.auto_mode,
                            color: AppTheme.limeAccentDark,
                          ),
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
                tooltip: 'Share',
                onPressed: (!_canAdminSelectFixtures || _isSharingFixtures)
                    ? null
                    : _shareSelectedFixturesToLeagueChat,
                icon: _isSharingFixtures
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: cs.primary,
                        ),
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
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final brightness = theme.brightness;

    final width = MediaQuery.of(context).size.width;
    final isTablet = width > 700;

    final mainBody = SafeArea(
      child: _isLoading
          ? Center(
              child: CircularProgressIndicator(color: AppTheme.limeAccentDark),
            )
          : (_loadError != null
              ? _buildLoadErrorState(_loadError!)
              : Center(
                  child: ConstrainedBox(
                    constraints:
                        BoxConstraints(maxWidth: isTablet ? 800 : 600),
                    child: RefreshIndicator(
                      onRefresh: _loadInitialData,
                      color: AppTheme.limeAccentDark,
                      backgroundColor: brightness == Brightness.light
                          ? Colors.white.withOpacity(0.92)
                          : cs.surface,
                      child: Column(
                        children: [
                          if (_format == LeagueFormat.uclGroup &&
                              _groups.isNotEmpty)
                            _buildGroupSelector(),
                          if (_totalRounds > 0)
                            _buildRoundSelector(_totalRounds),
                          Padding(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 16),
                            child: SectionHeader(
                              context.l10n.tr('fixtures_section_title'),
                            ),
                          ),
                          Expanded(child: _buildMatchesList()),
                        ],
                      ),
                    ),
                  ),
                )),
    );

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
        body: Stack(
          children: [
            mainBody,
            if (_sharePayload != null)
              Positioned.fill(
                child: _ShareCaptureOverlay(
                  repaintKey: _shareCardKey,
                  payload: _sharePayload!,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadErrorState(String msg) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Glass(
            borderRadius: 24,
            fill: AppTheme.cardColor(brightness),
            borderColor: AppTheme.cardBorder(brightness),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.cloud_off_rounded,
                    color: AppTheme.limeAccentDark,
                    size: 44,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Couldn’t load fixtures',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: AppTheme.primaryText(brightness),
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    msg,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: AppTheme.secondaryText(brightness),
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
                          style: FilledButton.styleFrom(
                            backgroundColor: AppTheme.limeAccent,
                            foregroundColor: AppTheme.darkText,
                          ),
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
    final theme = Theme.of(context);
    final brightness = theme.brightness;

    final unselectedBg = AppTheme.tabInactiveBackground(brightness);
    final unselectedBorder = AppTheme.cardBorder(brightness);
    final unselectedText = AppTheme.tabInactiveText(brightness);

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
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: allSelected
                    ? AppTheme.limeAccent
                    : unselectedBg,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: allSelected
                      ? AppTheme.limeAccentDark
                      : unselectedBorder,
                ),
                boxShadow: AppTheme.softCardShadow(brightness),
              ),
              alignment: Alignment.center,
              child: Text(
                l10n.tr('admin_score_all_groups'),
                style: TextStyle(
                  color: allSelected
                      ? AppTheme.darkText
                      : unselectedText,
                  fontWeight: FontWeight.w900,
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
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppTheme.limeAccent
                          : unselectedBg,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: isSelected
                            ? AppTheme.limeAccentDark
                            : unselectedBorder,
                      ),
                      boxShadow: AppTheme.softCardShadow(brightness),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      _groupDisplayName(l10n, group),
                      style: TextStyle(
                        color: isSelected
                            ? AppTheme.darkText
                            : unselectedText,
                        fontWeight: FontWeight.w900,
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
    final theme = Theme.of(context);
    final brightness = theme.brightness;

    final unselectedBg = AppTheme.tabInactiveBackground(brightness);
    final unselectedBorder = AppTheme.cardBorder(brightness);
    final unselectedText = AppTheme.tabInactiveText(brightness);

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
                color: isSelected
                    ? AppTheme.limeAccent
                    : unselectedBg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isSelected
                      ? AppTheme.limeAccentDark
                      : unselectedBorder,
                ),
                boxShadow: AppTheme.softCardShadow(brightness),
              ),
              alignment: Alignment.center,
              child: Text(
                '${l10n.tr('admin_score_round_prefix')}$round',
                style: TextStyle(
                  color: isSelected
                      ? AppTheme.darkText
                      : unselectedText,
                  fontWeight: FontWeight.w900,
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
    final brightness = Theme.of(context).brightness;

    final matches = _matchesForSelectedRound();

    if (matches.isEmpty) {
      return Center(
        child: Text(
          l10n.tr('fixtures_no_matches_generated_yet'),
          style: TextStyle(
            color: AppTheme.secondaryText(brightness),
            fontWeight: FontWeight.w600,
          ),
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
    final brightness = theme.brightness;

    final homeName = _teamNames[match.homeTeamId] ?? l10n.tr('fixtures_tbd');
    final awayName = _teamNames[match.awayTeamId] ?? l10n.tr('fixtures_tbd');
    final groupLabel =
        match.groupId?.trim().isNotEmpty == true ? match.groupId!.trim() : null;

    final homeUrl = (_teamImageUrls[match.homeTeamId] ?? '').trim();
    final awayUrl = (_teamImageUrls[match.awayTeamId] ?? '').trim();

    final isFinished =
        match.status == MatchStatus.completed || match.status == MatchStatus.played;
    final hasScore = match.homeScore != null && match.awayScore != null;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _handleFixtureTap(match),
      onLongPress:
          _canAdminSelectFixtures ? () => _handleFixtureLongPress(match) : null,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            color: selected
                ? (brightness == Brightness.dark
                    ? AppTheme.limeAccentDark.withOpacity(0.10)
                    : const Color(0xFFECFCCB))
                : Colors.transparent,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected
                  ? AppTheme.limeAccentDark
                  : Colors.transparent,
              width: 2,
            ),
            boxShadow: selected
                ? AppTheme.softCardShadow(brightness)
                : null,
          ),
          child: Stack(
            children: [
              Glass(
                padding: const EdgeInsets.all(16),
                fill: AppTheme.cardColor(brightness),
                borderColor: AppTheme.cardBorder(brightness),
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
                              color: AppTheme.secondaryText(brightness),
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
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
                                    fontWeight: FontWeight.w800,
                                    color: AppTheme.primaryText(brightness),
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
                                      color: AppTheme.limeAccentDark,
                                      fontWeight: FontWeight.w900,
                                      fontSize: 18,
                                    ),
                                  )
                                : Text(
                                    l10n.tr('league_details_vs'),
                                    style: theme.textTheme.labelLarge?.copyWith(
                                      color: AppTheme.secondaryText(brightness),
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
                                    fontWeight: FontWeight.w800,
                                    color: AppTheme.primaryText(brightness),
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
                    decoration: const BoxDecoration(
                      color: AppTheme.limeAccent,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.check,
                      size: 14,
                      color: AppTheme.darkText,
                    ),
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

  String _cloudinaryOptimizedUrl(String url,
      {int width = 64, int height = 64}) {
    final u = url.trim();
    if (u.isEmpty) return u;

    final isCloudinary =
        u.contains('res.cloudinary.com') && u.contains('/image/upload/');
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
    final isVersionOnly =
        first.startsWith('v') && int.tryParse(first.substring(1)) != null;

    if (!isVersionOnly) {
      if (first.contains('f_auto') || first.contains('q_auto')) return u;
      parts[0] = 'f_auto,q_auto,$first';
      return prefix + parts.join('/');
    }

    return '$prefix$transforms/$suffix';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;

    final raw = url.trim();
    final has = raw.isNotEmpty && _looksLikeHttpUrl(raw);
    final d = has ? _cloudinaryOptimizedUrl(raw, width: 64, height: 64) : '';

    final fill = AppTheme.searchBackground(brightness);
    final border = AppTheme.searchOutline(brightness);

    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        color: fill,
        shape: BoxShape.circle,
        border: Border.all(color: border),
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
                  color: AppTheme.secondaryText(brightness),
                ),
                loadingBuilder: (context, child, event) {
                  if (event == null) return child;
                  return Icon(
                    Icons.emoji_events_outlined,
                    size: 14,
                    color: AppTheme.secondaryText(brightness),
                  );
                },
              )
            : Icon(
                Icons.emoji_events_outlined,
                size: 14,
                color: AppTheme.secondaryText(brightness),
              ),
      ),
    );
  }
}

class _ShareCardPayload {
  final String leagueId;
  final String leagueName;
  final Uint8List? leagueLogoBytes;
  final LeagueFormat leagueFormat;
  final String? selectedGroup;
  final List<FixtureMatch> matches;
  final Map<String, String> teamNames;

  const _ShareCardPayload({
    required this.leagueId,
    required this.leagueName,
    required this.leagueLogoBytes,
    required this.leagueFormat,
    required this.selectedGroup,
    required this.matches,
    required this.teamNames,
  });
}

class _ShareCaptureOverlay extends StatelessWidget {
  const _ShareCaptureOverlay({
    required this.repaintKey,
    required this.payload,
  });

  final GlobalKey repaintKey;
  final _ShareCardPayload payload;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final brightness = theme.brightness;

    final statusFill = theme.brightness == Brightness.light
        ? Colors.white.withOpacity(0.92)
        : cs.surface.withOpacity(0.90);
    final statusBorder = theme.brightness == Brightness.light
        ? Colors.white.withOpacity(0.72)
        : cs.onSurface.withOpacity(0.18);

    return IgnorePointer(
      ignoring: true,
      child: Container(
        color: Colors.black.withOpacity(0.35),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  RepaintBoundary(
                    key: repaintKey,
                    child: _FixturesShareCard(payload: payload),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: statusFill,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: statusBorder),
                      boxShadow: AppTheme.softCardShadow(brightness),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: cs.primary),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          'Preparing share…',
                          style: TextStyle(
                            color: cs.onSurface.withOpacity(0.90),
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FixturesShareCard extends StatelessWidget {
  final _ShareCardPayload payload;

  const _FixturesShareCard({
    required this.payload,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final base = theme.brightness == Brightness.dark
        ? const Color(0xFF0B1220)
        : const Color(0xFFFFFFFF);

    final g1 = Color.alphaBlend(cs.primary.withOpacity(0.14), base);
    final g2 = Color.alphaBlend(cs.primary.withOpacity(0.06), base);

    final screenW = MediaQuery.of(context).size.width;
    final cardW = (screenW - 24).clamp(320.0, 720.0);

    final sorted = [...payload.matches];
    sorted.sort((a, b) {
      final r = a.roundNumber.compareTo(b.roundNumber);
      if (r != 0) return r;
      final si = a.sortIndex.compareTo(b.sortIndex);
      if (si != 0) return si;
      return a.id.compareTo(b.id);
    });

    const maxItems = 12;
    final shown = sorted.take(maxItems).toList(growable: false);
    final extra = math.max(0, sorted.length - shown.length);

    final subtitle = payload.leagueFormat == LeagueFormat.uclGroup &&
            (payload.selectedGroup ?? '').trim().isNotEmpty
        ? (payload.selectedGroup ?? '').trim()
        : '';

    final safeLeagueName =
        payload.leagueName.trim().isEmpty ? 'League' : payload.leagueName.trim();
    final logoBytes = payload.leagueLogoBytes;

    return Material(
      color: Colors.transparent,
      child: Container(
        width: cardW,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: base,
          borderRadius: BorderRadius.circular(22),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [g1, g2],
          ),
          border: Border.all(color: cs.onSurface.withOpacity(0.18)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(
                theme.brightness == Brightness.dark ? 0.45 : 0.16,
              ),
              blurRadius: 26,
              offset: const Offset(0, 14),
            ),
          ],
        ),
        child: DefaultTextStyle.merge(
          style: TextStyle(
            color: theme.brightness == Brightness.dark
                ? Colors.white
                : const Color(0xFF0B1220),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: Color.alphaBlend(
                          cs.primary.withOpacity(0.12), base),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: cs.primary.withOpacity(0.35)),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: (logoBytes != null && logoBytes.isNotEmpty)
                          ? Image.memory(logoBytes, fit: BoxFit.cover)
                          : Icon(Icons.emoji_events_rounded, color: cs.primary),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          safeLeagueName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w900,
                            color: (theme.brightness == Brightness.dark
                                    ? Colors.white
                                    : const Color(0xFF0B1220))
                                .withOpacity(0.78),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Fixtures',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                            color: theme.brightness == Brightness.dark
                                ? Colors.white
                                : const Color(0xFF0B1220),
                          ),
                        ),
                        if (subtitle.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              subtitle,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: (theme.brightness == Brightness.dark
                                        ? Colors.white
                                        : const Color(0xFF0B1220))
                                    .withOpacity(0.75),
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 7),
                    decoration: BoxDecoration(
                      color: Color.alphaBlend(
                          cs.onSurface.withOpacity(0.06), base),
                      borderRadius: BorderRadius.circular(999),
                      border:
                          Border.all(color: cs.onSurface.withOpacity(0.18)),
                    ),
                    child: Text(
                      '${payload.matches.length} selected',
                      style: TextStyle(
                        color: (theme.brightness == Brightness.dark
                                ? Colors.white
                                : const Color(0xFF0B1220))
                            .withOpacity(0.85),
                        fontWeight: FontWeight.w900,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Divider(height: 1, color: cs.onSurface.withOpacity(0.18)),
              const SizedBox(height: 12),
              for (final m in shown) ...[
                _FixturesShareRow(
                  base: base,
                  round: m.roundNumber,
                  groupLabel: (m.groupId ?? '').trim(),
                  homeName:
                      (payload.teamNames[m.homeTeamId] ?? 'TBD').trim(),
                  awayName:
                      (payload.teamNames[m.awayTeamId] ?? 'TBD').trim(),
                  homeScore: m.homeScore,
                  awayScore: m.awayScore,
                ),
                const SizedBox(height: 10),
              ],
              if (extra > 0) ...[
                const SizedBox(height: 2),
                Text(
                  '+$extra more',
                  style: TextStyle(
                    color: (theme.brightness == Brightness.dark
                            ? Colors.white
                            : const Color(0xFF0B1220))
                        .withOpacity(0.70),
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                  ),
                ),
              ],
              const SizedBox(height: 10),
              Divider(height: 1, color: cs.onSurface.withOpacity(0.18)),
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(Icons.lock_outline_rounded,
                      size: 16, color: cs.onSurface.withOpacity(0.65)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Shared from fixtures',
                      style: TextStyle(
                        color: (theme.brightness == Brightness.dark
                                ? Colors.white
                                : const Color(0xFF0B1220))
                            .withOpacity(0.75),
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  Text(
                    'eSportlyic league',
                    style: TextStyle(
                      color: cs.primary.withOpacity(0.95),
                      fontWeight: FontWeight.w900,
                      fontSize: 12,
                      letterSpacing: 0.2,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FixturesShareRow extends StatelessWidget {
  const _FixturesShareRow({
    required this.base,
    required this.round,
    required this.groupLabel,
    required this.homeName,
    required this.awayName,
    required this.homeScore,
    required this.awayScore,
  });

  final Color base;

  final int round;
  final String groupLabel;
  final String homeName;
  final String awayName;
  final int? homeScore;
  final int? awayScore;

  bool get _hasScore => homeScore != null && awayScore != null;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final isDark = theme.brightness == Brightness.dark;
    final fg = isDark ? Colors.white : const Color(0xFF0B1220);

    final group = groupLabel.trim();
    final roundChip = 'R$round';
    final scoreText = _hasScore ? '$homeScore  -  $awayScore' : 'vs';

    final rowBg = Color.alphaBlend(
      cs.onSurface.withOpacity(isDark ? 0.10 : 0.04),
      base,
    );
    final rowBorder = cs.onSurface.withOpacity(0.18);

    final scoreBg = Color.alphaBlend(
      _hasScore
          ? cs.primary.withOpacity(0.16)
          : cs.onSurface.withOpacity(isDark ? 0.10 : 0.06),
      base,
    );

    final matchup = '${homeName.trim()} vs ${awayName.trim()}';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: rowBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: rowBorder),
      ),
      child: Row(
        children: [
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Color.alphaBlend(
                    cs.primary.withOpacity(0.16),
                    base,
                  ),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: cs.primary.withOpacity(0.30)),
                ),
                child: Text(
                  roundChip,
                  style: TextStyle(
                    color: cs.primary,
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                  ),
                ),
              ),
              if (group.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  group,
                  style: TextStyle(
                    color: fg.withOpacity(0.70),
                    fontWeight: FontWeight.w900,
                    fontSize: 11,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              matchup,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w900,
                color: fg.withOpacity(0.96),
                height: 1.1,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: scoreBg,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: _hasScore
                    ? cs.primary.withOpacity(0.30)
                    : cs.onSurface.withOpacity(0.18),
              ),
            ),
            child: Text(
              scoreText,
              style: TextStyle(
                color: _hasScore
                    ? cs.primary.withOpacity(0.98)
                    : fg.withOpacity(0.75),
                fontWeight: FontWeight.w900,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
