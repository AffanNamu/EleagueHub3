//lib/core/services/chat_audio_playback_controller.dart
//
// Single, app-wide voice-message playback controller. Mirrors the
// "only one player, switch source, only one message plays at a time"
// behaviour every chat screen used to reimplement locally — the
// difference now is it always plays from a local file already fetched by
// ChatMediaCacheService, so playback never depends on Cloudinary/network
// availability once a voice note has been downloaded.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import 'chat_media_cache_service.dart';

class ChatAudioPlaybackController extends ChangeNotifier {
  ChatAudioPlaybackController._internal();

  static final ChatAudioPlaybackController instance =
      ChatAudioPlaybackController._internal();

  final AudioPlayer _player = AudioPlayer();

  StreamSubscription<Duration>? _posSub;
  StreamSubscription<Duration?>? _durSub;
  StreamSubscription<PlayerState>? _stateSub;
  Timer? _positionPersistTimer;
  bool _wired = false;

  String? _activeUrl;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _playing = false;

  String? get activeUrl => _activeUrl;
  Duration get position => _position;
  Duration get duration => _duration;

  bool isActive(String url) => _activeUrl == url;
  bool isPlaying(String url) => _activeUrl == url && _playing;

  void _ensureWired() {
    if (_wired) return;
    _wired = true;

    _posSub = _player.positionStream.listen((p) {
      _position = p;
      notifyListeners();
    });

    _durSub = _player.durationStream.listen((d) {
      _duration = d ?? Duration.zero;
      final url = _activeUrl;
      if (url != null && _duration.inMilliseconds > 0) {
        unawaited(
          ChatMediaCacheService.instance
              .setVoiceDurationMs(url, _duration.inMilliseconds),
        );
      }
      notifyListeners();
    });

    _stateSub = _player.playerStateStream.listen((s) {
      final completed = s.processingState == ProcessingState.completed;
      _playing = s.playing && !completed;
      if (completed) {
        _position = Duration.zero;
        _persistPosition(resetToZero: true);
      }
      notifyListeners();
    });
  }

  /// Starts (or resumes) playback of [url] from the given local file.
  /// If [url] is already the active track, this behaves like a toggle.
  Future<void> playLocalFile({
    required String url,
    required String localPath,
    int resumeFromMs = 0,
  }) async {
    _ensureWired();

    if (_activeUrl == url) {
      if (_player.playing) {
        await pause();
      } else {
        await _player.play();
      }
      return;
    }

    _persistPosition();
    _positionPersistTimer?.cancel();
    await _player.stop();

    _activeUrl = url;
    _position = Duration(milliseconds: resumeFromMs);
    _duration = Duration.zero;
    notifyListeners();

    await _player.setFilePath(localPath);
    if (resumeFromMs > 0) {
      await _player.seek(Duration(milliseconds: resumeFromMs));
    }
    await _player.play();
    _startPositionPersistTimer();
  }

  /// Convenience combining "start if not active" / "pause if playing" /
  /// "replay if finished" / "resume otherwise" into one call for a single
  /// play/pause button.
  Future<void> toggle({
    required String url,
    required String localPath,
    int resumeFromMs = 0,
  }) async {
    _ensureWired();

    if (_activeUrl != url) {
      await playLocalFile(url: url, localPath: localPath, resumeFromMs: resumeFromMs);
      return;
    }

    final atEnd = _duration > Duration.zero &&
        (_duration - _position) <= const Duration(milliseconds: 250);

    if (_playing) {
      await pause();
    } else if (atEnd) {
      await replay();
    } else {
      await _player.play();
    }
  }

  Future<void> pause() async {
    await _player.pause();
    _positionPersistTimer?.cancel();
    _persistPosition();
  }

  Future<void> seekTo(Duration d) async {
    final clamped = d < Duration.zero
        ? Duration.zero
        : (_duration > Duration.zero && d > _duration ? _duration : d);
    await _player.seek(clamped);
  }

  Future<void> seekBy(Duration delta) => seekTo(_position + delta);

  Future<void> replay() async {
    await _player.seek(Duration.zero);
    await _player.play();
    _startPositionPersistTimer();
  }

  void _startPositionPersistTimer() {
    _positionPersistTimer?.cancel();
    _positionPersistTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      _persistPosition();
    });
  }

  void _persistPosition({bool resetToZero = false}) {
    final url = _activeUrl;
    if (url == null) return;
    final ms = resetToZero ? 0 : _position.inMilliseconds;
    unawaited(ChatMediaCacheService.instance.setPlaybackPositionMs(url, ms));
  }

  @override
  void dispose() {
    _positionPersistTimer?.cancel();
    _posSub?.cancel();
    _durSub?.cancel();
    _stateSub?.cancel();
    _player.dispose();
    super.dispose();
  }
}
