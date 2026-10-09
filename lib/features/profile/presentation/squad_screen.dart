//lib/features/profile/presentation/squad_screen.dart
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../../core/locale/app_localizations.dart';
import '../../../core/services/connectivity_service.dart';
import '../../../core/services/safe_image_picker.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/cloudinary_utils.dart';
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
  static const int _maxSquadPhotoBytes = 5 * 1024 * 1024;

  final TeamProfileRepository _repo = TeamProfileRepository();

  String _selectedGame = GameId.localFootball;
  List<String> _availableGames = [GameId.localFootball];
  bool _loadingGames = true;

  bool _editMode = false;

  // NEW: real squad/team photo upload (Feature — Squad photo).
  bool _uploadingSquadPhoto = false;

  @override
  void initState() {
    super.initState();
    _loadAvailableGames();
  }

  Future<void> _loadAvailableGames() async {
    try {
      // resolveDisplayGameIds falls back to the user's onboarding choice
      // (users/{uid}.preferredGameId) when no squad has been built yet —
      // true for every new user — instead of hardcoding Local Football
      // regardless of what they actually picked.
      final ids = await _repo.resolveDisplayGameIds(widget.userId);
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

  // ── NEW: Squad photo upload ────────────────────────────────────────────
  //
  // A real photo of the user's actual squad/team, distinct from the
  // per-player photos on the virtual pitch. Uploaded here (owner only),
  // shown to everyone here AND on the public team profile (see
  // PublicTeamProfileScreen's _SquadPreview), mirroring the existing
  // cover-photo upload pattern in public_team_profile_screen.dart.

  Future<String> _uploadSquadPhotoToCloudinary(PlatformFile picked) async {
    final cloudName = const String.fromEnvironment('CLOUDINARY_CLOUD_NAME').trim();
    final uploadPreset =
        const String.fromEnvironment('CLOUDINARY_UNSIGNED_UPLOAD_PRESET').trim();
    if (cloudName.isEmpty || uploadPreset.isEmpty) {
      throw StateError(context.l10n.tr('squad_screen_cloudinary_not_configured_error'));
    }

    final uploadUrl = Uri.parse('https://api.cloudinary.com/v1_1/$cloudName/image/upload');
    final ts = DateTime.now().millisecondsSinceEpoch;

    http.MultipartFile filePart;
    final bytes = picked.bytes;
    final path = (picked.path ?? '').trim();

    if (bytes != null && bytes.isNotEmpty) {
      filePart = http.MultipartFile.fromBytes('file', bytes, filename: picked.name);
    } else if (path.isNotEmpty) {
      filePart = await http.MultipartFile.fromPath('file', path, filename: picked.name);
    } else {
      throw StateError(context.l10n.tr('squad_screen_image_not_accessible_error'));
    }

    final req = http.MultipartRequest('POST', uploadUrl)
      ..fields['upload_preset'] = uploadPreset
      ..fields['resource_type'] = 'image'
      ..fields['folder'] = 'eleaguehub/squad_photos'
      ..fields['public_id'] = 'squad_photo_${_selectedGame}_$ts'
      ..files.add(filePart);

    final client = http.Client();
    try {
      final streamed = await client.send(req).timeout(const Duration(seconds: 45));
      final resp = await http.Response.fromStream(streamed).timeout(const Duration(seconds: 45));

      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        final l10n = context.l10n;
        String message =
            '${l10n.tr('squad_screen_upload_failed_http_prefix')}${resp.statusCode}${l10n.tr('squad_screen_upload_failed_http_suffix')}';
        try {
          final decoded = jsonDecode(resp.body);
          final err = (decoded is Map<String, dynamic>) ? decoded['error'] : null;
          final msg = (err is Map<String, dynamic>) ? (err['message']?.toString() ?? '') : '';
          if (msg.trim().isNotEmpty) {
            message = '${l10n.tr('squad_screen_upload_failed_prefix')}${msg.trim()}';
          }
        } catch (_) {}
        throw StateError(message);
      }

      final decoded = jsonDecode(resp.body);
      if (decoded is! Map<String, dynamic>) {
        throw StateError(context.l10n.tr('squad_screen_upload_failed_invalid_response'));
      }
      final secureUrl = (decoded['secure_url']?.toString() ?? '').trim();
      if (secureUrl.isEmpty) {
        throw StateError(context.l10n.tr('squad_screen_upload_failed_missing_url'));
      }
      return secureUrl;
    } finally {
      client.close();
    }
  }

  Future<void> _pickAndUploadSquadPhoto() async {
    if (_uploadingSquadPhoto) return;
    if (!widget.isOwner) return;

    setState(() => _uploadingSquadPhoto = true);
    try {
      await ConnectivityService.instance.requireOnline(timeout: const Duration(seconds: 6));

      final pickResult = await SafeImagePicker.pickImage();
      if (pickResult.wasCancelled) return;
      if (!pickResult.isSuccess) {
        _snack(pickResult.errorMessage ?? context.l10n.tr('squad_screen_pick_image_failed_fallback'));
        return;
      }

      final picked = pickResult.file!;
      if (picked.size > _maxSquadPhotoBytes) {
        _snack(context.l10n.tr('squad_screen_image_too_large_message'));
        return;
      }

      final secureUrl = await _uploadSquadPhotoToCloudinary(picked);
      await _repo.updateSquadPhoto(gameId: _selectedGame, squadPhotoUrl: secureUrl);

      if (!mounted) return;
      _snack(context.l10n.tr('squad_screen_photo_updated_snackbar'));
    } catch (e) {
      _snack(e.toString());
    } finally {
      if (mounted) setState(() => _uploadingSquadPhoto = false);
    }
  }

  Future<void> _confirmRemoveSquadPhoto() async {
    final l10n = context.l10n;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.tr('squad_screen_remove_photo_confirm_title')),
        content: Text(l10n.tr('squad_screen_remove_photo_confirm_message')),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(l10n.tr('common_cancel'))),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: Text(l10n.tr('profile_remove_button'))),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _uploadingSquadPhoto = true);
    try {
      await _repo.updateSquadPhoto(gameId: _selectedGame, squadPhotoUrl: '');
      if (!mounted) return;
      _snack(l10n.tr('squad_screen_photo_removed_snackbar'));
    } catch (e) {
      _snack(e.toString());
    } finally {
      if (mounted) setState(() => _uploadingSquadPhoto = false);
    }
  }

  void _showSquadPhotoSheet({required bool hasPhoto}) {
    final l10n = context.l10n;
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_back_rounded),
              title: Text(hasPhoto
                  ? l10n.tr('squad_screen_change_photo_label')
                  : l10n.tr('squad_screen_upload_photo_label')),
              onTap: () {
                Navigator.of(ctx).pop();
                _pickAndUploadSquadPhoto();
              },
            ),
            if (hasPhoto)
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded),
                title: Text(l10n.tr('squad_screen_remove_photo_label')),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _confirmRemoveSquadPhoto();
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _editStartingSlot(Squad squad, int slotIndex) async {
    final slots = FormationPresets.slotsFor(squad.formation);
    if (slotIndex < 0 || slotIndex >= slots.length) return;

    final slotLabel = slots[slotIndex].label;

    SquadPlayerSlot? existing;
    for (final p in squad.startingXI) {
      if (p.slotIndex == slotIndex) {
        existing = p;
        break;
      }
    }

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
    final l10n = context.l10n;

    return GlassScaffold(
      appBar: AppBar(
        title: Text(l10n.tr('public_profile_section_squad')),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          if (widget.isOwner)
            IconButton(
              tooltip: _editMode
                  ? l10n.tr('squad_screen_done_editing_tooltip')
                  : l10n.tr('squad_screen_edit_squad_tooltip'),
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
                            SnackBar(
                              behavior: SnackBarBehavior.floating,
                              content: Text(
                                l10n.tr('squad_screen_new_game_hint_snackbar'),
                              ),
                              duration: const Duration(seconds: 4),
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
                              _SquadPhotoCard(
                                photoUrl: squad.squadPhotoUrl,
                                isOwner: widget.isOwner,
                                uploading: _uploadingSquadPhoto,
                                onTap: () => _showSquadPhotoSheet(
                                  hasPhoto: squad.squadPhotoUrl.trim().isNotEmpty,
                                ),
                              ),
                              const SizedBox(height: 16),
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
                                onPlayerMoved: (playerId, x, y) =>
                                    _persistSquad(squad.withPlayerPosition(playerId, x, y)),
                                onPlayerSwap: (a, b) =>
                                    _persistSquad(squad.withPlayersSwapped(a, b)),
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
      final updated = current.withFormationApplied(formation);
      await _repo.saveSquad(updated);
    } catch (e) {
      _snack(e.toString());
    }
  }
}

class _SquadPhotoCard extends StatelessWidget {
  const _SquadPhotoCard({
    required this.photoUrl,
    required this.isOwner,
    required this.uploading,
    required this.onTap,
  });

  final String photoUrl;
  final bool isOwner;
  final bool uploading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final hasPhoto = photoUrl.trim().isNotEmpty;

    // Visitors (non-owners) with no photo uploaded see nothing here —
    // no empty placeholder card cluttering their view.
    if (!hasPhoto && !isOwner) return const SizedBox.shrink();

    return GestureDetector(
      onTap: isOwner ? onTap : null,
      child: Container(
        height: hasPhoto ? 180 : 90,
        width: double.infinity,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          color: AppTheme.cardColor(brightness),
          border: Border.all(color: AppTheme.cardBorder(brightness)),
          image: hasPhoto
              ? DecorationImage(image: NetworkImage(CloudinaryUtils.fill(photoUrl, width: 700, height: 360)), fit: BoxFit.cover)
              : null,
        ),
        child: Stack(
          children: [
            if (!hasPhoto)
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.groups_rounded, color: AppTheme.secondaryText(brightness)),
                    const SizedBox(height: 4),
                    Text(
                      context.l10n.tr('squad_screen_add_photo_placeholder'),
                      style: TextStyle(
                        color: AppTheme.secondaryText(brightness),
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            if (uploading)
              Container(
                color: Colors.black.withOpacity(0.35),
                child: const Center(
                  child: SizedBox(
                    width: 26,
                    height: 26,
                    child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                  ),
                ),
              ),
            if (isOwner && hasPhoto && !uploading)
              Positioned(
                right: 8,
                top: 8,
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.5),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.edit_rounded, size: 16, color: Colors.white),
                ),
              ),
          ],
        ),
      ),
    );
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
              label: Text(context.l10n.tr('squad_screen_add_game_label')),
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
