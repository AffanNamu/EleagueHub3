import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../data/player_photo_service.dart';
import '../../models/squad.dart';

/// Bottom sheet for creating/editing one player slot. Returns the
/// updated SquadPlayerSlot, or null if the sheet was dismissed, or a
/// special "delete" signal via [_DeleteSentinel] when the user removes
/// the player.
class PlayerEditResult {
  const PlayerEditResult.save(this.player) : deleted = false;
  const PlayerEditResult.delete()
      : player = null,
        deleted = true;

  final SquadPlayerSlot? player;
  final bool deleted;
}

Future<PlayerEditResult?> showPlayerEditSheet(
  BuildContext context, {
  required String slotLabel,
  SquadPlayerSlot? existing,
  required bool isStarting,
}) {
  return showModalBottomSheet<PlayerEditResult>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => _PlayerEditSheet(
      slotLabel: slotLabel,
      existing: existing,
      isStarting: isStarting,
    ),
  );
}

class _PlayerEditSheet extends StatefulWidget {
  const _PlayerEditSheet({
    required this.slotLabel,
    required this.existing,
    required this.isStarting,
  });

  final String slotLabel;
  final SquadPlayerSlot? existing;
  final bool isStarting;

  @override
  State<_PlayerEditSheet> createState() => _PlayerEditSheetState();
}

class _PlayerEditSheetState extends State<_PlayerEditSheet> {
  late final TextEditingController _nameController =
      TextEditingController(text: widget.existing?.name ?? '');
  late final TextEditingController _numberController = TextEditingController(
    text: widget.existing != null && widget.existing!.shirtNumber > 0
        ? '${widget.existing!.shirtNumber}'
        : '',
  );

  final PlayerPhotoService _photoService = PlayerPhotoService();

  Timer? _debounce;
  bool _searching = false;
  bool _resolvingPhoto = false;
  bool _suppressNextSearch = false;
  List<PlayerSearchCandidate> _candidates = const [];
  String? _searchError;

  /// The photo actually saved when the sheet closes. Starts pre-filled
  /// if editing a player that already has one.
  late String _resolvedPhotoUrl = widget.existing?.photoUrl ?? '';

  /// Raw preview URL shown WHILE a Cloudinary resolve is in flight (so
  /// the user sees something immediately instead of a blank circle).
  String _previewPhotoUrl = '';

  @override
  void initState() {
    super.initState();
    _previewPhotoUrl = _resolvedPhotoUrl;
    _nameController.addListener(_onNameChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _nameController.removeListener(_onNameChanged);
    _nameController.dispose();
    _numberController.dispose();
    super.dispose();
  }

  void _onNameChanged() {
    if (_suppressNextSearch) {
      _suppressNextSearch = false;
      return;
    }

    // Any manual edit after a photo was resolved invalidates that photo —
    // the name no longer necessarily matches the real player it came from.
    if (_resolvedPhotoUrl.isNotEmpty || _previewPhotoUrl.isNotEmpty) {
      setState(() {
        _resolvedPhotoUrl = '';
        _previewPhotoUrl = '';
      });
    }

    _debounce?.cancel();
    final query = _nameController.text.trim();

    if (query.length < 3) {
      if (_candidates.isNotEmpty || _searchError != null) {
        setState(() {
          _candidates = const [];
          _searchError = null;
          _searching = false;
        });
      }
      return;
    }

    _debounce = Timer(const Duration(milliseconds: 350), () => _runSearch(query));
  }

  Future<void> _runSearch(String query) async {
    if (!mounted) return;
    setState(() {
      _searching = true;
      _searchError = null;
    });

    try {
      final results = await _photoService.searchPlayers(query);
      if (!mounted) return;
      // The user may have kept typing while this was in flight — only
      // apply results if the query is still current.
      if (_nameController.text.trim() != query) return;
      setState(() {
        _candidates = results;
        _searching = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _searching = false;
        _searchError = e.toString();
      });
    }
  }

  Future<void> _selectCandidate(PlayerSearchCandidate candidate) async {
    _suppressNextSearch = true;
    setState(() {
      _nameController.text = candidate.name;
      _nameController.selection = TextSelection.collapsed(offset: candidate.name.length);
      _candidates = const [];
      _searchError = null;
      _previewPhotoUrl = candidate.previewPhotoUrl;
      _resolvingPhoto = candidate.bestPhotoUrl.isNotEmpty;
      _resolvedPhotoUrl = '';
    });

    if (candidate.bestPhotoUrl.isEmpty) return;

    try {
      final resolved = await _photoService.resolvePhotoUrl(candidate.bestPhotoUrl);
      if (!mounted) return;
      setState(() {
        _resolvedPhotoUrl = resolved;
        _resolvingPhoto = false;
        if (resolved.isNotEmpty) _previewPhotoUrl = resolved;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _resolvingPhoto = false);
    }
  }

  void _save() {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;

    final number = int.tryParse(_numberController.text.trim()) ?? 0;

    final player = SquadPlayerSlot(
      playerId: widget.existing?.playerId ?? _generateId(),
      name: name,
      position: widget.slotLabel,
      x: widget.existing?.x ?? 0,
      y: widget.existing?.y ?? 0,
      isStarting: widget.isStarting,
      shirtNumber: number.clamp(0, 99),
      slotIndex: widget.existing?.slotIndex ?? -1,
      photoUrl: _resolvedPhotoUrl,
    );

    Navigator.of(context).pop(PlayerEditResult.save(player));
  }

  String _generateId() =>
      'p_${DateTime.now().microsecondsSinceEpoch}_${widget.slotLabel}';

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final hasExisting = widget.existing != null && widget.existing!.name.trim().isNotEmpty;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${widget.slotLabel} — ${widget.isStarting ? "Starting XI" : "Bench"}',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                  color: AppTheme.primaryText(brightness),
                ),
              ),
              const SizedBox(height: 16),
              Center(child: _PhotoPreview(url: _previewPhotoUrl, resolving: _resolvingPhoto)),
              const SizedBox(height: 16),
              TextField(
                controller: _nameController,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Player name'),
              ),
              if (_searching)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: LinearProgressIndicator(minHeight: 2),
                ),
              if (_searchError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    _searchError!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              if (_candidates.isNotEmpty) ...[
                const SizedBox(height: 8),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 220),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppTheme.cardBorder(brightness)),
                      color: AppTheme.cardColor(brightness),
                    ),
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: _candidates.length,
                      separatorBuilder: (_, __) =>
                          Divider(height: 1, color: AppTheme.cardBorder(brightness)),
                      itemBuilder: (context, i) {
                        final c = _candidates[i];
                        final subtitleParts = <String>[
                          if (c.team.isNotEmpty) c.team,
                          if (c.position.isNotEmpty) c.position,
                          if (c.nationality.isNotEmpty) c.nationality,
                        ];
                        return ListTile(
                          dense: true,
                          leading: CircleAvatar(
                            radius: 18,
                            backgroundColor: AppTheme.iconCircleBackground(brightness),
                            backgroundImage: c.previewPhotoUrl.isNotEmpty
                                ? NetworkImage(c.previewPhotoUrl)
                                : null,
                            child: c.previewPhotoUrl.isEmpty
                                ? Icon(Icons.person, color: AppTheme.primaryText(brightness))
                                : null,
                          ),
                          title: Text(
                            c.name,
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              color: AppTheme.primaryText(brightness),
                            ),
                          ),
                          subtitle: subtitleParts.isEmpty
                              ? null
                              : Text(
                                  subtitleParts.join(' • '),
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: AppTheme.secondaryText(brightness),
                                  ),
                                ),
                          onTap: () => _selectCandidate(c),
                        );
                      },
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: _numberController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Shirt number (optional)'),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  if (hasExisting) ...[
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(foregroundColor: Colors.redAccent),
                        onPressed: () => Navigator.of(context)
                            .pop(const PlayerEditResult.delete()),
                        icon: const Icon(Icons.delete_outline_rounded),
                        label: const Text('Remove'),
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: FilledButton(
                      onPressed: _save,
                      child: const Text('Save'),
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

class _PhotoPreview extends StatelessWidget {
  const _PhotoPreview({required this.url, required this.resolving});

  final String url;
  final bool resolving;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;

    return Stack(
      alignment: Alignment.center,
      children: [
        CircleAvatar(
          radius: 40,
          backgroundColor: AppTheme.iconCircleBackground(brightness),
          backgroundImage: url.isNotEmpty ? NetworkImage(url) : null,
          child: url.isEmpty
              ? Icon(Icons.person, size: 36, color: AppTheme.primaryText(brightness))
              : null,
        ),
        if (resolving)
          const SizedBox(
            width: 80,
            height: 80,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
      ],
    );
  }
}
