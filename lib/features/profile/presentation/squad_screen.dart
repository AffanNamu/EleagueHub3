import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/glass.dart';
import '../../../core/widgets/glass_scaffold.dart';
import '../data/team_profile_repository.dart';
import '../models/formation_presets.dart';
import '../models/game_id.dart';
import '../models/squad.dart';
import 'widgets/player_edit_sheet.dart';
import 'widgets/squad_pitch_view.dart';

class SquadScreen extends ConsumerStatefulWidget {
  const SquadScreen({
    super.key,
    required this.userId,
    required this.isOwner,
  });

  final String userId;
  final bool isOwner;

  @override
  ConsumerState<SquadScreen> createState() => _SquadScreenState();
}

class _SquadScreenState extends ConsumerState<SquadScreen> {
  final TeamProfileRepository _repo = TeamProfileRepository();

  String _selectedGame = GameId.localFootball;
  List<String> _availableGames = [GameId.localFootball];
  bool _loadingGames = true;

  bool _editMode = false;

  @override
  void initState() {
    super.initState();
    _loadAvailableGames();
  }

  Future<void> _loadAvailableGames() async {
    try {
      final ids = await _repo.fetchSquadGameIds(widget.userId);
      if (!mounted) return;
      setState(() {
        _availableGames = ids.isEmpty ? [GameId.localFootball] : ids;
        _selectedGame = _availableGames.first;
        _loadingGames = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingGames = false);
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(behavior: SnackBarBehavior.floating, content: Text(msg)),
    );
  }

  Future<void> _editStartingSlot(Squad squad, int slotIndex) async {
    final slots = FormationPresets.slotsFor(squad.formation);
    if (slotIndex < 0 || slotIndex >= slots.length) return;

    final slotLabel = slots[slotIndex].label;
    final starters = squad.startingXI;
    final existing = slotIndex < starters.length ? starters[slotIndex] : null;

    final result = await showPlayerEditSheet(
      context,
      slotLabel: slotLabel,
      existing: existing,
      isStarting: true,
    );
    if (result == null) return;

    Squad updated;
    if (result.deleted) {
      updated = squad.withStarterRemovedAtSlot(slotIndex);
    } else {
      updated = squad.withStarterAtSlot(slotIndex, result.player!);
    }

    await _persistSquad(updated);
  }

  Future<void> _addBenchPlayer(Squad squad) async {
    final result = await showPlayerEditSheet(
      context,
      slotLabel: 'SUB',
      existing: null,
      isStarting: false,
    );
    if (result == null || result.deleted) return;

    await _persistSquad(squad.withBenchPlayerAdded(result.player!));
  }

  Future<void> _editBenchPlayer(Squad squad, SquadPlayerSlot player) async {
    final result = await showPlayerEditSheet(
      context,
      slotLabel: player.position.isEmpty ? 'SUB' : player.position,
      existing: player,
      isStarting: false,
    );
    if (result == null) return;

    Squad updated;
    if (result.deleted) {
      updated = squad.withPlayerRemoved(player.playerId);
    } else {
      updated = squad.withPlayerRemoved(player.playerId).withBenchPlayerAdded(result.player!);
    }

    await _persistSquad(updated);
  }

  Future<void> _persistSquad(Squad squad) async {
    try {
      await _repo.saveSquad(Squad(
        gameId: squad.gameId,
        formation: squad.formation,
        players: squad.players,
        managerName: squad.managerName,
        captainPlayerId: squad.captainPlayerId,
        viceCaptainPlayerId: squad.viceCaptainPlayerId,
        teamStrength: squad.teamStrength,
        updatedAtMs: DateTime.now().millisecondsSinceEpoch,
      ));
    } catch (e) {
      _snack(e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;

    return GlassScaffold(
      appBar: AppBar(
        title: const Text('Squad'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          if (widget.isOwner)
            IconButton(
              tooltip: _editMode ? 'Done editing' : 'Edit squad',
              icon: Icon(_editMode ? Icons.check_rounded : Icons.edit_rounded),
              onPressed: () => setState(() => _editMode = !_editMode),
            ),
        ],
      ),
      body: SafeArea(
        child: _loadingGames
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  _GameSwitcher(
                    games: _availableGames,
                    selected: _selectedGame,
                    onSelect: (g) => setState(() => _selectedGame = g),
                    allowAddGame: widget.isOwner,
                    onAddGame: (g) {
                      if (!_availableGames.contains(g)) {
                        setState(() {
                          _availableGames = [..._availableGames, g];
                          _selectedGame = g;
                          _editMode = true; // drop straight into edit mode
                        });
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              behavior: SnackBarBehavior.floating,
                              content: Text(
                                'Pick a formation and add at least one player, '
                                'then it will be saved to your profile.',
                              ),
                              duration: Duration(seconds: 4),
                            ),
                          );
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: StreamBuilder<Squad>(
                        key: ValueKey(_selectedGame),
                        stream: _repo.watchSquad(
                          userId: widget.userId,
                          gameId: _selectedGame,
                        ),
                        builder: (context, snap) {
                          if (!snap.hasData) {
                            return const Padding(
                              padding: EdgeInsets.symmetric(vertical: 60),
                              child: Center(child: CircularProgressIndicator()),
                            );
                          }
                          final squad = snap.data!;
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (widget.isOwner && _editMode)
                                _FormationSelector(
                                  current: squad.formation,
                                  onSelect: (f) => _saveFormation(squad, f),
                                ),
                              if (widget.isOwner && _editMode)
                                const SizedBox(height: 16),
                              SquadPitchView(
                                squad: squad,
                                isEditable: widget.isOwner && _editMode,
                                onSlotTap: (i) => _editStartingSlot(squad, i),
                                onAddBenchPlayer: () => _addBenchPlayer(squad),
                                onEditBenchPlayer: (p) => _editBenchPlayer(squad, p),
                                onSetCaptain: (id) => _persistSquad(squad.withCaptain(id)),
                                onSetViceCaptain: (id) => _persistSquad(squad.withViceCaptain(id)),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Future<void> _saveFormation(Squad current, String formation) async {
    try {
      final updated = Squad(
        gameId: current.gameId,
        formation: formation,
        players: current.players,
        managerName: current.managerName,
        captainPlayerId: current.captainPlayerId,
        viceCaptainPlayerId: current.viceCaptainPlayerId,
        teamStrength: current.teamStrength,
        updatedAtMs: DateTime.now().millisecondsSinceEpoch,
      );
      await _repo.saveSquad(updated);
    } catch (e) {
      _snack(e.toString());
    }
  }
}

class _GameSwitcher extends StatelessWidget {
  const _GameSwitcher({
    required this.games,
    required this.selected,
    required this.onSelect,
    required this.allowAddGame,
    required this.onAddGame,
  });

  final List<String> games;
  final String selected;
  final ValueChanged<String> onSelect;
  final bool allowAddGame;
  final ValueChanged<String> onAddGame;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final addable = GameId.all.where((g) => !games.contains(g)).toList();

    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          for (final g in games) ...[
            _chip(context, GameId.label(g), g == selected, () => onSelect(g)),
            const SizedBox(width: 8),
          ],
          if (allowAddGame && addable.isNotEmpty)
            ActionChip(
              avatar: const Icon(Icons.add_rounded, size: 16),
              label: const Text('Add game'),
              onPressed: () async {
                final choice = await showModalBottomSheet<String>(
                  context: context,
                  builder: (ctx) => SafeArea(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: addable
                          .map((g) => ListTile(
                                title: Text(GameId.label(g)),
                                onTap: () => Navigator.of(ctx).pop(g),
                              ))
                          .toList(),
                    ),
                  ),
                );
                if (choice != null) onAddGame(choice);
              },
            ),
        ],
      ),
    );
  }

  Widget _chip(BuildContext context, String label, bool selected,
      VoidCallback onTap) {
    final brightness = Theme.of(context).brightness;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      selectedColor: AppTheme.limeAccent,
      labelStyle: TextStyle(
        fontWeight: FontWeight.w800,
        fontSize: 12,
        color: selected ? AppTheme.darkText : AppTheme.primaryText(brightness),
      ),
      backgroundColor: AppTheme.cardColor(brightness),
      side: BorderSide(color: AppTheme.cardBorder(brightness)),
    );
  }
}

class _FormationSelector extends StatelessWidget {
  const _FormationSelector({required this.current, required this.onSelect});
  final String current;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: FormationPresets.supported
          .map(
            (f) => ChoiceChip(
              label: Text(f),
              selected: f == current,
              onSelected: (_) => onSelect(f),
              selectedColor: AppTheme.limeAccent,
              labelStyle: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 12,
                color: f == current
                    ? AppTheme.darkText
                    : AppTheme.primaryText(brightness),
              ),
              backgroundColor: AppTheme.cardColor(brightness),
              side: BorderSide(color: AppTheme.cardBorder(brightness)),
            ),
          )
          .toList(),
    );
  }
}
