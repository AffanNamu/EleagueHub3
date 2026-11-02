// lib/features/chat/presentation/widgets/voice_record_controls.dart
//
// Telegram-style press-and-hold voice recording, with pause/resume on top
// (which Telegram itself doesn't have): a mic button that starts recording
// on press, pauses on release (showing explicit Cancel/Pause-or-Resume/Send
// controls -- never auto-sends), cancels if you slide left past a
// threshold, and locks into hands-free *active* recording if you slide up
// past a threshold instead of pausing (so you can lift your finger and keep
// talking). Either way, once the finger is up, the same persistent control
// row is shown, so there's always a visible way to pause what you're
// recording, resume it later, send it, or discard it -- nothing happens
// silently on release. Shared by every chat screen's input bar so the
// gesture, thresholds, and visuals stay identical everywhere.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;

import '../../../../core/locale/app_localizations.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/glass.dart';

/// How far (in logical pixels) the finger must slide left to arm
/// "slide to cancel" (cancels on release past this point).
const double voiceRecordCancelThresholdPx = 90;

/// How far (in logical pixels) the finger must slide up to lock into
/// hands-free recording.
const double voiceRecordLockThresholdPx = 70;

/// Live drag state reported while a press-and-hold recording gesture is
/// active, so the parent screen's [RecordingOverlay] can animate in sync
/// with the actual finger position.
class VoiceRecordDrag {
  const VoiceRecordDrag({
    required this.cancelProgress,
    required this.lockProgress,
  });

  /// 0.0 (not dragged) to 1.0 (at/past the cancel threshold).
  final double cancelProgress;

  /// 0.0 (not dragged) to 1.0 (at/past the lock threshold).
  final double lockProgress;
}

/// The press-and-hold mic button itself. Purely a gesture surface + its own
/// icon -- the actual "recording in progress" feedback (timer, slide-to-cancel
/// hint, lock) is [RecordingOverlay], shown by the parent screen above this
/// button while [onRecordStart] is active.
class VoiceRecordButton extends StatefulWidget {
  const VoiceRecordButton({
    super.key,
    required this.enabled,
    required this.onRecordStart,
    required this.onRecordCancel,
    required this.onRecordPause,
    required this.onRecordLock,
    this.onDragUpdate,
    this.onQuickTap,
    this.size = 48,
  });

  final bool enabled;

  /// Finger pressed down: begin recording immediately.
  final VoidCallback onRecordStart;

  /// Finger released past the cancel threshold (or the gesture was
  /// otherwise interrupted, e.g. another gesture winning): discard the
  /// recording.
  final VoidCallback onRecordCancel;

  /// Finger released over/near the button, not past the cancel threshold,
  /// and not locked: PAUSE the recording (never auto-send) and hand off to
  /// the caller's persistent Cancel/Resume/Send controls (see
  /// [RecordingOverlay]'s locked state -- pausing on release puts it in
  /// that same state, just starting out paused).
  final VoidCallback onRecordPause;

  /// Finger dragged up past the lock threshold: recording continues
  /// hands-free (NOT paused). The caller is now responsible for its own
  /// explicit Cancel/Pause/Send controls (see [RecordingOverlay]'s locked
  /// state) -- this button stops tracking the gesture once locked.
  final VoidCallback onRecordLock;

  /// Fires on every drag update while recording and not yet locked, so the
  /// parent can animate its slide-to-cancel / lock hints in lockstep with
  /// the actual finger position. Not required -- a caller that doesn't need
  /// live visual feedback can omit it.
  final ValueChanged<VoiceRecordDrag>? onDragUpdate;

  /// A quick tap -- released before the long-press deadline, so none of
  /// the onRecord* callbacks above fire at all. By design (same as
  /// Telegram) a tap never starts a recording, but a tap in total
  /// silence with no feedback whatsoever reads as "this button is
  /// broken" rather than "hold it down" -- this gives the caller a hook
  /// to show that hint (a toast/snackbar). A light haptic always fires
  /// on tap regardless of whether this is set, so the press itself is
  /// never silent even without a caller-provided hint.
  final VoidCallback? onQuickTap;

  final double size;

  @override
  State<VoiceRecordButton> createState() => _VoiceRecordButtonState();
}

class _VoiceRecordButtonState extends State<VoiceRecordButton> {
  Offset? _startGlobalPos;
  bool _tracking = false;
  bool _locked = false;

  void _reset() {
    _startGlobalPos = null;
    _tracking = false;
    _locked = false;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      // Coexists fine with the onLongPress* handlers below -- a release
      // before the long-press deadline resolves as a tap, a sustained
      // hold resolves as a long press; GestureDetector arbitrates this
      // itself since both recognizers belong to the same detector.
      onTap: !widget.enabled
          ? null
          : () {
              HapticFeedback.selectionClick();
              widget.onQuickTap?.call();
            },
      onLongPressStart: !widget.enabled
          ? null
          : (details) {
              _startGlobalPos = details.globalPosition;
              _tracking = true;
              _locked = false;
              widget.onDragUpdate?.call(
                const VoiceRecordDrag(cancelProgress: 0, lockProgress: 0),
              );
              widget.onRecordStart();
            },
      onLongPressMoveUpdate: (details) {
        if (!_tracking || _locked) return;
        final start = _startGlobalPos;
        if (start == null) return;

        final dx = (start.dx - details.globalPosition.dx)
            .clamp(0, voiceRecordCancelThresholdPx)
            .toDouble();
        final dy = (start.dy - details.globalPosition.dy)
            .clamp(0, voiceRecordLockThresholdPx)
            .toDouble();

        final cancelProgress = dx / voiceRecordCancelThresholdPx;
        final lockProgress = dy / voiceRecordLockThresholdPx;
        widget.onDragUpdate?.call(
          VoiceRecordDrag(cancelProgress: cancelProgress, lockProgress: lockProgress),
        );

        if (lockProgress >= 1.0) {
          _locked = true;
          _tracking = false;
          widget.onRecordLock();
        } else if (cancelProgress >= 1.0) {
          _locked = false;
          _tracking = false;
          _startGlobalPos = null;
          widget.onRecordCancel();
        }
      },
      onLongPressEnd: (details) {
        if (!_tracking) return;
        _reset();
        widget.onRecordPause();
      },
      onLongPressCancel: () {
        if (!_tracking) return;
        _reset();
        widget.onRecordCancel();
      },
      child: Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: widget.enabled ? cs.primary : cs.onSurface.withOpacity(0.14),
        ),
        child: Icon(
          Icons.mic,
          size: 20,
          color: widget.enabled ? cs.onPrimary : cs.onSurface.withOpacity(0.45),
        ),
      ),
    );
  }
}

/// Shown above the input bar while a press-and-hold voice recording is in
/// progress (mirrors Telegram's own recording bar): a pulsing red dot with
/// a live timer, a "< Slide to cancel" hint that tracks the drag, and a lock
/// icon that fills in as the user drags toward it. Once [locked] is true
/// (either the user explicitly locked it, or just released without
/// canceling -- see [VoiceRecordButton.onRecordPause]), switches to
/// persistent Cancel / Pause-or-Resume / Send buttons, so there's always a
/// visible way to finish this recording regardless of whether the finger
/// is still down.
class RecordingOverlay extends StatefulWidget {
  const RecordingOverlay({
    super.key,
    required this.recordedMsBeforePause,
    required this.activeSegmentStartedAt,
    required this.drag,
    required this.locked,
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

  final VoiceRecordDrag drag;
  final bool locked;

  /// Only meaningful once [locked] -- whether audio capture is currently
  /// paused (true) or actively recording hands-free (false).
  final bool paused;

  final bool isSending;
  final VoidCallback onCancel;
  final VoidCallback onSend;

  /// Toggles between pausing the active recording and resuming a paused
  /// one. Only shown once [locked].
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
        child: widget.locked
            ? Row(
                children: [
                  Icon(
                    widget.paused ? Icons.pause_circle_outline_rounded : Icons.lock_rounded,
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
              )
            : Row(
                children: [
                  FadeTransition(
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
                  const SizedBox(width: 10),
                  Text(
                    _fmt(_elapsed),
                    style: TextStyle(
                      color: AppTheme.primaryText(brightness),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const Spacer(),
                  // Slides left as the user drags toward the cancel
                  // threshold, fading as it approaches -- matches the
                  // button's own cancelProgress 1:1 so letting go exactly
                  // when the hint reaches its faintest is exactly when it
                  // cancels.
                  Transform.translate(
                    offset: Offset(-voiceRecordCancelThresholdPx * 0.4 * widget.drag.cancelProgress, 0),
                    child: Opacity(
                      opacity: 1.0 - (widget.drag.cancelProgress * 0.7),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.chevron_left_rounded,
                              color: AppTheme.secondaryText(brightness), size: 18),
                          Text(
                            context.l10n.tr('chat_input_slide_to_cancel'),
                            style: TextStyle(
                              color: AppTheme.secondaryText(brightness),
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  // Fills in / rises slightly as the user drags toward the
                  // lock threshold.
                  Transform.translate(
                    offset: Offset(0, -6 * widget.drag.lockProgress),
                    child: Icon(
                      Icons.lock_outline_rounded,
                      size: 18,
                      color: Color.lerp(
                        AppTheme.secondaryText(brightness),
                        cs.primary,
                        widget.drag.lockProgress,
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
