import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/persistence/prefs_service.dart';
import '../../../core/widgets/glass.dart';
import '../../../core/widgets/glass_scaffold.dart';
import '../../../core/widgets/section_header.dart';
import '../data/leagues_repository_local.dart';
import '../domain/algorithms/swiss_pairing.dart';
import '../logic/fixture_generator.dart';
import '../models/fixture_match.dart';
import '../models/enums.dart';
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

LeagueFormat _format = LeagueFormat.classic;
List<String> _groups = [];

/// null = "All groups" when format == uclGroup
String? _selectedGroup;
int _selectedRound = 1;

bool _isGenerating = false;
void _toast(String msg, {Color bg = const Color(0xFF101522), Color fg = Colors.white}) {
if (!mounted) return;
ScaffoldMessenger.of(context).clearSnackBars();
ScaffoldMessenger.of(context).showSnackBar(
SnackBar(
behavior: SnackBarBehavior.floating,
margin: const EdgeInsets.all(12),
backgroundColor: bg,
content: Text(msg, style: TextStyle(color: fg, fontWeight: FontWeight.w600)),
duration: const Duration(seconds: 3),
),
);
}
void _toastOk(String msg) => _toast(msg, bg: Colors.cyanAccent.withOpacity(0.18), fg: Colors.cyanAccent);
void _toastWarn(String msg) => _toast(msg, bg: Colors.orangeAccent.withOpacity(0.14), fg: Colors.orangeAccent);
void _toastErr(String msg) => _toast(msg, bg: Colors.redAccent.withOpacity(0.14), fg: Colors.redAccent);

@override
void initState() {
super.initState();
_repo = LocalLeaguesRepository(ref.read(prefsServiceProvider));
_loadData();
}

Future<void> _loadData() async {
if (!mounted) return;
setState(() => _isLoading = true);
final leagueFuture = _repo.getLeagueById(widget.leagueId);
final matchesFuture = _repo.getMatches(widget.leagueId);
final teamsFuture = _repo.getTeams(widget.leagueId);

final league = await leagueFuture;
final matches = await matchesFuture;
final teams = await teamsFuture;

final format = league?.format ?? LeagueFormat.classic;

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

if (!mounted) return;
setState(() {
  _league = league;
  _teams = teams;
  _format = format;
  _groups = groups;
  _selectedGroup = selectedGroup;
  _matches = matches;
  _teamNames = {for (var t in teams) t.id: t.name};
  _selectedRound = selectedRound;
  _isLoading = false;
});
}
Future<void> _updateScore(
FixtureMatch match,
int hScore,
int aScore,
) async {
final updatedMatch = match.copyWith(
homeScore: hScore,
awayScore: aScore,
status: MatchStatus.completed,
updatedAtMs: DateTime.now().millisecondsSinceEpoch,
);
await _repo.saveMatches(widget.leagueId, [updatedMatch]);

if (mounted) {
  _toastOk('Score Updated Successfully');
  _loadData();
}
}
bool get _hasAnyMatches => _matches.isNotEmpty;

bool get _hasGroupFixtures =>
_matches.any((m) => (m.groupId ?? '').trim().isNotEmpty);

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
if (_isGenerating) return;
if (_league == null) return;
if (_teams.length < 2) {
  _toastErr('Not enough teams to generate fixtures.');
  return;
}
if (_hasAnyMatches) {
  _toastWarn('Fixtures already exist.');
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
    _toastErr('Failed to generate fixtures.');
    return;
  }

  await _repo.saveMatches(widget.leagueId, fixtures);
  _toastOk('Fixtures generated (${fixtures.length} matches).');
  await _loadData();
} finally {
  if (mounted) setState(() => _isGenerating = false);
}
}
Future<void> _generateGroupFixtures() async {
if (_isGenerating) return;
if (_league == null) return;
if (!_isGroupValidTeamCount) {
  _toastErr('UCL Group supports only 16 or 32 teams. Current: ${_teams.length}.');
  return;
}
if (!_groupsAssignedAndFull()) {
  _toastWarn('Complete group draw first (all groups must have exactly 4 teams).');
  return;
}
if (_hasGroupFixtures) {
  _toastWarn('Group fixtures already exist.');
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
    _toastErr('Failed to generate group fixtures.');
    return;
  }

  await _repo.saveMatches(widget.leagueId, fixtures);
  _toastOk('Group fixtures generated (${fixtures.length} matches).');
  await _loadData();
} finally {
  if (mounted) setState(() => _isGenerating = false);
}

}
Future<void> _generateNextSwissRound() async {
if (_isGenerating) return;
if (_league == null) return;
if (!_isSwissValidTeamCount) {
  _toastErr('Swiss format supports only 18 or 36 teams. Current: ${_teams.length}.');
  return;
}
if (_teams.length.isOdd) {
  _toastErr('Swiss league phase requires an even number of teams (no byes).');
  return;
}

setState(() => _isGenerating = true);
try {
  final maxRounds = _league!.settings.swissRounds;

  final existing = await _repo.getMatches(widget.leagueId);
  int currentMaxRound = 0;
  if (existing.isNotEmpty) {
    currentMaxRound = existing.map((m) => m.roundNumber).reduce((a, b) => a > b ? a : b);
  }

  // Require completion of current round before generating next
  if (currentMaxRound > 0) {
    final currentRoundMatches = existing.where((m) => m.roundNumber == currentMaxRound).toList();
    final anyUnplayed = currentRoundMatches.any((m) => !m.isPlayed);
    if (anyUnplayed) {
      _toastWarn('Complete all matches in Round $currentMaxRound before generating the next round.');
      return;
    }
  }

  if (currentMaxRound >= maxRounds) {
    _toastWarn('All $maxRounds Swiss rounds have already been generated.');
    return;
  }

  final nextRound = currentMaxRound == 0 ? 1 : currentMaxRound + 1;

  // Prevent duplicates
  final alreadyExists = existing.any((m) => m.roundNumber == nextRound);
  if (alreadyExists) {
    _toastWarn('Round $nextRound already exists.');
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
    _toastErr('No Swiss pairings could be generated.');
    return;
  }

  await _repo.saveMatches(widget.leagueId, newFixtures);
  _toastOk('Swiss round $nextRound generated (${newFixtures.length} matches).');
  await _loadData();
} finally {
  if (mounted) setState(() => _isGenerating = false);
}
}
@override
Widget build(BuildContext context) {
final width = MediaQuery.of(context).size.width;
final isTablet = width > 700;
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

final showGenerateClassic = _format == LeagueFormat.classic && !_hasAnyMatches;
final showGenerateGroup = _format == LeagueFormat.uclGroup && !_hasGroupFixtures;
final showGenerateSwiss = _format == LeagueFormat.uclSwiss;

return GlassScaffold(
  appBar: AppBar(
    title: const Text("Score Management"),
    backgroundColor: Colors.transparent,
    elevation: 0,
  ),
  body: SafeArea(
    child: _isLoading
        ? const Center(
            child: CircularProgressIndicator(color: Colors.cyanAccent),
          )
        : Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: isTablet ? 1000 : 500),
              child: Column(
                children: [
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: SectionHeader('Update Match Results'),
                  ),
                  const SizedBox(height: 6),

                  // Fixture generation controls (admin-only screen)
                  if (showGenerateClassic || showGenerateGroup || showGenerateSwiss)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Column(
                        children: [
                          if (showGenerateClassic)
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: _isGenerating ? null : _generateClassicFixtures,
                                icon: _isGenerating
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.cyanAccent),
                                      )
                                    : const Icon(Icons.auto_awesome, color: Colors.cyanAccent),
                                label: const Text(
                                  'GENERATE CLASSIC FIXTURES',
                                  style: TextStyle(fontWeight: FontWeight.w900),
                                ),
                              ),
                            ),
                          if (showGenerateGroup)
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: _isGenerating ? null : _generateGroupFixtures,
                                icon: _isGenerating
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.cyanAccent),
                                      )
                                    : const Icon(Icons.groups_2, color: Colors.cyanAccent),
                                label: const Text(
                                  'GENERATE GROUP FIXTURES',
                                  style: TextStyle(fontWeight: FontWeight.w900),
                                ),
                              ),
                            ),
                          if (showGenerateSwiss)
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: _isGenerating ? null : _generateNextSwissRound,
                                icon: _isGenerating
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.cyanAccent),
                                      )
                                    : const Icon(Icons.auto_mode, color: Colors.cyanAccent),
                                label: const Text(
                                  'GENERATE NEXT SWISS ROUND',
                                  style: TextStyle(fontWeight: FontWeight.w900),
                                ),
                              ),
                            ),
                          const SizedBox(height: 6),
                        ],
                      ),
                    ),

                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: Text(
                      'Tap + / - to adjust each team\'s score.\n'
                      'Use group and round filters to quickly find matches.\n'
                      'Pending matches are listed first; completed go to the bottom.',
                      style: TextStyle(color: Colors.white30, fontSize: 12),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 8),

                  if (_format == LeagueFormat.uclGroup && _groups.isNotEmpty) _buildGroupSelector(),
                  if (availableRounds.isNotEmpty) _buildRoundSelector(availableRounds),

                  const SizedBox(height: 4),
                  Expanded(
                    child: visibleMatches.isEmpty
                        ? const Center(
                            child: Text(
                              "No matches to manage",
                              style: TextStyle(color: Colors.white38),
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.all(16),
                            itemCount: visibleMatches.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 12),
                            itemBuilder: (context, index) {
                              final match = visibleMatches[index];
                              return _ScoreEntryTile(
                                key: ValueKey(match.id),
                                match: match,
                                homeName: _teamNames[match.homeTeamId] ?? "Home",
                                awayName: _teamNames[match.awayTeamId] ?? "Away",
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
final bool allSelected = _selectedGroup == null;
return Container(
  height: 40,
  margin: const EdgeInsets.symmetric(horizontal: 16),
  child: ListView(
    scrollDirection: Axis.horizontal,
    children: [
      GestureDetector(
        onTap: () {
          Iterable<FixtureMatch> forRounds = _matches;
          final roundSet = forRounds.map((m) => m.roundNumber).toSet();
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
          margin: const EdgeInsets.only(right: 8),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: allSelected ? Colors.cyanAccent : Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: allSelected ? Colors.cyanAccent : Colors.white10,
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            'All',
            style: TextStyle(
              color: allSelected ? Colors.black : Colors.white70,
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
                Iterable<FixtureMatch> forRounds = _matches.where((m) => m.groupId == group);
                final roundSet = forRounds.map((m) => m.roundNumber).toSet();
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
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: isSelected ? Colors.cyanAccent : Colors.white.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: isSelected ? Colors.cyanAccent : Colors.white10,
                  ),
                ),
                alignment: Alignment.center,
                child: Text(
                  group,
                  style: TextStyle(
                    color: isSelected ? Colors.black : Colors.white70,
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
margin: const EdgeInsets.only(right: 10),
padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
decoration: BoxDecoration(
color: isSelected ? Colors.cyanAccent : Colors.white.withOpacity(0.05),
borderRadius: BorderRadius.circular(12),
border: Border.all(
color: isSelected ? Colors.cyanAccent : Colors.white10,
),
),
alignment: Alignment.center,
child: Text(
'RD $round',
style: TextStyle(
color: isSelected ? Colors.black : Colors.white70,
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
final Function(int, int) onSave;
const _ScoreEntryTile({
super.key,
required this.match,
required this.homeName,
required this.awayName,
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
bool get _isCompleted =>
widget.match.status == MatchStatus.completed || widget.match.status == MatchStatus.played;

void _incHome() => setState(() => _homeScore++);
void _decHome() => setState(() {
if (_homeScore > 0) _homeScore--;
});

void _incAway() => setState(() => _awayScore++);
void _decAway() => setState(() {
if (_awayScore > 0) _awayScore--;
});

@override
Widget build(BuildContext context) {
final groupLabel = widget.match.groupId?.trim().isNotEmpty == true ? widget.match.groupId!.trim() : null;
return Glass(
  padding: const EdgeInsets.all(18),
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (groupLabel != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              groupLabel,
              style: const TextStyle(
                color: Colors.white54,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      Row(
        children: [
          Expanded(
            child: Text(
              widget.homeName,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              "VS",
              style: TextStyle(
                color: Colors.white24,
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          Expanded(
            child: Text(
              widget.awayName,
              textAlign: TextAlign.end,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: _isCompleted ? Colors.cyanAccent.withOpacity(0.12) : Colors.white.withOpacity(0.04),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              _isCompleted ? 'Completed' : 'Pending',
              style: TextStyle(
                color: _isCompleted ? Colors.cyanAccent : Colors.white54,
                fontSize: 11,
                fontWeight: FontWeight.w600,
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
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              ":",
              style: TextStyle(
                color: Colors.white38,
                fontSize: 24,
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
            onPressed: () {
              widget.onSave(_homeScore, _awayScore);
              FocusScope.of(context).unfocus();
            },
            style: IconButton.styleFrom(
              backgroundColor: Colors.cyanAccent.withOpacity(0.2),
              foregroundColor: Colors.cyanAccent,
            ),
            icon: const Icon(Icons.done_all, size: 24),
          ),
        ],
      ),
    ],
  ),
);
}
Widget _scoreStepper({
required int value,
required VoidCallback onInc,
required VoidCallback onDec,
}) {
return Container(
decoration: BoxDecoration(
color: Colors.white.withOpacity(0.05),
borderRadius: BorderRadius.circular(12),
border: Border.all(color: Colors.white10),
),
padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
child: Row(
mainAxisSize: MainAxisSize.min,
children: [
_stepperButton(
icon: Icons.remove,
onPressed: value > 0 ? onDec : null,
enabled: value > 0,
),
const SizedBox(width: 6),
SizedBox(
width: 28,
child: Text(
'$value',
textAlign: TextAlign.center,
style: const TextStyle(
color: Colors.white,
fontSize: 22,
fontWeight: FontWeight.w900,
),
),
),
const SizedBox(width: 6),
_stepperButton(
icon: Icons.add,
onPressed: onInc,
enabled: true,
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
return InkWell(
onTap: onPressed,
borderRadius: BorderRadius.circular(20),
child: Container(
width: 28,
height: 28,
decoration: BoxDecoration(
color: enabled ? Colors.cyanAccent.withOpacity(0.08) : Colors.white.withOpacity(0.02),
shape: BoxShape.circle,
),
child: Icon(
icon,
size: 18,
color: enabled ? Colors.cyanAccent : Colors.white24,
),
),
);
}
}
