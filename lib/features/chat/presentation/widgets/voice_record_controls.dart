// lib/features/chat/presentation/widgets/voice_record_controls.dart
//
// Tap-to-record voice messages: touching the mic button starts recording
// the instant the finger touches down (not on release -- see
// VoiceRecordButton's onTapDown) -- no press-and-hold delay, no drag
// gesture, nothing to miss, and holding does the same thing a quick tap
// does. The moment it starts, the caller's persistent RecordingOverlay
// takes over with explicit Pause/Resume, Cancel, and Send controls,
// actively recording (never paused) until the user explicitly taps pause
// -- release never pauses or stops it. Shared by every chat screen's input
// bar so the behavior and visuals stay identical everywhere.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;

import '../../../../core/locale/app_localizations.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/glass.dart';

/// The mic button itself. Purely a tap surface + its own icon -- the actual
/// "recording in progress" feedback (timer, Pause/Resume, Cancel, Send) is
/// [RecordingOverlay], shown by the parent screen above this button while a
/// recording is in progress.
class VoiceRecordButton extends StatelessWidget {
  const VoiceRecordButton({
    super.key,
    required this.enabled,
    required this.onRecordStart,
    this.size = 48,
  });

  final bool enabled;

  /// Touched: begin recording immediately. Fires on touch-DOWN (see
  /// onTapDown below), not on release, so a sustained hold starts
  /// recording the instant the finger lands rather than waiting for it to
  /// lift -- release carries no special meaning at all once recording has
  /// started. The caller's RecordingOverlay (Pause/Resume/Cancel/Send)
  /// takes over from there -- this button has nothing left to do once a
  /// recording is in progress.
  final VoidCallback onRecordStart;

  final double size;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      // onTapDown (not onTap) deliberately -- onTap only fires once the
      // finger lifts, which would make a sustained hold sit there doing
      // nothing until release. onTapDown fires the instant the finger
      // touches down, so both a quick tap and a long hold start recording
      // immediately and identically.
      onTapDown: !enabled
          ? null
          : (_) {
              HapticFeedback.selectionClick();
              onRecordStart();
            },
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: enabled ? cs.primary : cs.onSurface.withOpacity(0.14),
        ),
        child: Icon(
          Icons.mic,
          size: 20,
          color: enabled ? cs.onPrimary : cs.onSurface.withOpacity(0.45),
        ),
      ),
    );
  }
}

/// Shown above the input bar while a recording is in progress: a timer with
/// a pulsing (or, while paused, static) dot, and persistent Pause/Resume,
/// Cancel, and Send controls -- always visible the instant recording
/// starts, so there's always a clear way to pause, resume, send, or discard
/// it.
class RecordingOverlay extends StatefulWidget {
  const RecordingOverlay({
    super.key,
    required this.recordedMsBeforePause,
    required this.activeSegmentStartedAt,
    required this.paused,
    required this.isSending,
    required this.onCancel,
    required this.onSend,
    required this.onPauseResume,
  });

  /// Total duration actually captured across every prior recording segment
  /// (i.e. not counting time spent paused). Frozen while [paused].
  final int recordedMsBeforePause;

  /// When the CURRENT segment started actively capturing -- null while
  /// [paused] (there is no active segment to measure). Used together with
  /// [recordedMsBeforePause] to show a live timer that correctly excludes
  /// paused gaps, and that freezes the instant a pause happens.
  final DateTime? activeSegmentStartedAt;

  /// Whether audio capture is currently paused (true) or actively
  /// recording (false).
  final bool paused;

  final bool isSending;
  final VoidCallback onCancel;
  final VoidCallback onSend;

  /// Toggles between pausing the active recording and resuming a paused
  /// one.
  final VoidCallback onPauseResume;

  @override
  State<RecordingOverlay> createState() => _RecordingOverlayState();
}

class _RecordingOverlayState extends State<RecordingOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  Timer? _ticker;
  Duration _elapsed = Duration.zero;

  @override
  void initState() {
    super.initState();
    _tick();
    _ticker = Timer.periodic(const Duration(milliseconds: 500), (_) => _tick());
  }

  void _tick() {
    if (!mounted) return;
    final segmentStart = widget.activeSegmentStartedAt;
    final activeMs =
        segmentStart == null ? 0 : DateTime.now().difference(segmentStart).inMilliseconds;
    setState(() {
      _elapsed = Duration(milliseconds: widget.recordedMsBeforePause + activeMs);
    });
  }

  String _fmt(Duration d) {
    final mm = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final ss = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$mm:$ss';
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      child: Glass(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Icon(
              widget.paused ? Icons.pause_circle_outline_rounded : Icons.mic_rounded,
              color: cs.primary,
              size: 18,
            ),
            const SizedBox(width: 10),
            widget.paused
                ? Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppTheme.secondaryText(brightness),
                    ),
                  )
                : FadeTransition(
                    opacity: _pulse,
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.redAccent,
                      ),
                    ),
                  ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _fmt(_elapsed),
                style: TextStyle(
                  color: AppTheme.primaryText(brightness),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: widget.paused
                  ? context.l10n.tr('chat_input_resume_recording_tooltip')
                  : context.l10n.tr('chat_input_pause_recording_tooltip'),
              onPressed: widget.isSending ? null : widget.onPauseResume,
              icon: Icon(
                widget.paused ? Icons.mic_rounded : Icons.pause_rounded,
                color: cs.primary,
              ),
            ),
            TextButton(
              onPressed: widget.isSending ? null : widget.onCancel,
              child: Text(context.l10n.tr('common_cancel')),
            ),
            const SizedBox(width: 6),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.limeAccent,
                foregroundColor: AppTheme.darkText,
              ),
              onPressed: widget.isSending ? null : widget.onSend,
              child: widget.isSending
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(Icons.send_rounded, size: 18),
            ),
          ],
        ),
      ),
    );
  }
}
