import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
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

  @override
  void dispose() {
    _nameController.dispose();
    _numberController.dispose();
    super.dispose();
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
              TextField(
                controller: _nameController,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Player name'),
              ),
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
