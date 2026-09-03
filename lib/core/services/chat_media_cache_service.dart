//lib/core/services/chat_media_cache_service.dart
//
// WhatsApp-style on-demand media cache for chat images and voice notes.
//
// Design goals (see redesign requirements):
// - Nothing downloads automatically when a chat opens.
// - Explicit Download action fetches once, persists locally, and is reused
//   instantly (and offline) afterwards.
// - Concurrent taps / multiple bubbles referencing the same URL never
//   trigger duplicate downloads (in-flight de-dup keyed by URL).
// - Downloads are cancellable and retryable, survive app restart (manifest
//   persisted via SharedPreferences, files under the app's documents dir),
//   and the cache is bounded with LRU eviction.
// - Voice notes additionally track a best-effort duration (probed once
//   after download) and last playback position (for resume-from-position).
//
// Uses only packages already in pubspec.yaml: dio (progress + cancellation),
// path_provider (persistent storage location), shared_preferences (manifest),
// just_audio (duration probing). No new dependencies added.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/cloudinary_media_utils.dart';
import 'connectivity_service.dart';

enum ChatMediaKind { image, voice }

enum ChatMediaPhase { notDownloaded, downloading, downloaded, failed }

@immutable
class ChatMediaDownloadState {
  final ChatMediaPhase phase;

  /// 0..1, only meaningful while [phase] is [ChatMediaPhase.downloading].
  final double progress;

  /// Set once [phase] is [ChatMediaPhase.downloaded].
  final String? localPath;

  /// Set once [phase] is [ChatMediaPhase.failed].
  final String? errorMessage;

  const ChatMediaDownloadState._(
    this.phase,
    this.progress,
    this.localPath,
    this.errorMessage,
  );

  const ChatMediaDownloadState.notDownloaded()
      : this._(ChatMediaPhase.notDownloaded, 0, null, null);

  const ChatMediaDownloadState.downloading(double progress)
      : this._(ChatMediaPhase.downloading, progress, null, null);

  const ChatMediaDownloadState.downloaded(String path)
      : this._(ChatMediaPhase.downloaded, 1, path, null);

  const ChatMediaDownloadState.failed(String message)
      : this._(ChatMediaPhase.failed, 0, null, message);

  bool get isDownloaded => phase == ChatMediaPhase.downloaded;
  bool get isDownloading => phase == ChatMediaPhase.downloading;
  bool get isFailed => phase == ChatMediaPhase.failed;
}

class _CacheRecord {
  final String url;
  final ChatMediaKind kind;
  String localPath;
  int sizeBytes;
  int downloadedAtMs;
  int lastAccessMs;
  int? durationMs; // voice only
  int? positionMs; // voice only — last playback position, for resume

  _CacheRecord({
    required this.url,
    required this.kind,
    required this.localPath,
    required this.sizeBytes,
    required this.downloadedAtMs,
    required this.lastAccessMs,
    this.durationMs,
    this.positionMs,
  });

  Map<String, dynamic> toJson() => <String, dynamic>{
        'url': url,
        'kind': kind == ChatMediaKind.image ? 'image' : 'voice',
        'localPath': localPath,
        'sizeBytes': sizeBytes,
        'downloadedAtMs': downloadedAtMs,
        'lastAccessMs': lastAccessMs,
        if (durationMs != null) 'durationMs': durationMs,
        if (positionMs != null) 'positionMs': positionMs,
      };

  static _CacheRecord? fromJson(Map<String, dynamic> json) {
    final url = (json['url'] as String? ?? '').trim();
    final localPath = (json['localPath'] as String? ?? '').trim();
    if (url.isEmpty || localPath.isEmpty) return null;

    int _int(dynamic v) => v is int ? v : (v is num ? v.toInt() : 0);
    int? _intOrNull(dynamic v) =>
        v == null ? null : (v is int ? v : (v is num ? v.toInt() : null));

    return _CacheRecord(
      url: url,
      kind: json['kind'] == 'voice' ? ChatMediaKind.voice : ChatMediaKind.image,
      localPath: localPath,
      sizeBytes: _int(json['sizeBytes']),
      downloadedAtMs: _int(json['downloadedAtMs']),
      lastAccessMs: _int(json['lastAccessMs']),
      durationMs: _intOrNull(json['durationMs']),
      positionMs: _intOrNull(json['positionMs']),
    );
  }
}

/// Thrown for user-facing download failures. Mirrors the existing
/// `UserFriendlyException` pattern used by `ConnectivityService`.
class ChatMediaException implements Exception {
  final String message;
  const ChatMediaException(this.message);

  @override
  String toString() => message;
}

class ChatMediaCacheService {
  ChatMediaCacheService._internal();

  static final ChatMediaCacheService instance =
      ChatMediaCacheService._internal();

  static const String _prefsKey = 'chat_media_cache_manifest_v1';
  static const int _maxCacheBytes = 300 * 1024 * 1024; // 300 MB budget

  final Dio _dio = Dio();

  final Map<String, _CacheRecord> _records = <String, _CacheRecord>{};
  final Map<String, ValueNotifier<ChatMediaDownloadState>> _notifiers =
      <String, ValueNotifier<ChatMediaDownloadState>>{};
  final Set<String> _hydrated = <String>{};
  final Map<String, Future<String>> _inFlight = <String, Future<String>>{};
  final Map<String, CancelToken> _cancelTokens = <String, CancelToken>{};

  bool _loaded = false;
  Future<void>? _loading;

  Future<void> _ensureLoaded() {
    if (_loaded) return Future.value();
    return _loading ??= _loadFromPrefs();
  }

  Future<void> _loadFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          for (final item in decoded) {
            if (item is Map<String, dynamic>) {
              final record = _CacheRecord.fromJson(item);
              if (record != null) _records[record.url] = record;
            } else if (item is Map) {
              final record =
                  _CacheRecord.fromJson(Map<String, dynamic>.from(item));
              if (record != null) _records[record.url] = record;
            }
          }
        }
      }
    } catch (_) {
      // Corrupt manifest — start fresh rather than crash the chat screen.
    } finally {
      _loaded = true;
      _loading = null;
    }
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = _records.values.map((r) => r.toJson()).toList();
      await prefs.setString(_prefsKey, jsonEncode(list));
    } catch (_) {
      // Best-effort — a failed manifest write just means the entry is
      // re-downloaded next app launch, which is acceptable.
    }
  }

  ValueNotifier<ChatMediaDownloadState> _notifierFor(String url) {
    return _notifiers.putIfAbsent(
      url,
      () => ValueNotifier<ChatMediaDownloadState>(
        const ChatMediaDownloadState.notDownloaded(),
      ),
    );
  }

  /// A per-URL, listenable download/cache status. Widgets can build off
  /// this directly with `ValueListenableBuilder` — no polling required.
  /// The first call for a given URL kicks off a one-time async check of
  /// whether the media is already cached on disk (e.g. from a previous
  /// session) and updates the notifier accordingly.
  ValueListenable<ChatMediaDownloadState> watch(String url) {
    final trimmed = url.trim();
    final notifier = _notifierFor(trimmed);
    if (!_hydrated.contains(trimmed)) {
      _hydrated.add(trimmed);
      unawaited(_hydrate(trimmed, notifier));
    }
    return notifier;
  }

  Future<void> _hydrate(
    String url,
    ValueNotifier<ChatMediaDownloadState> notifier,
  ) async {
    final path = await cachedPath(url);
    if (path != null) {
      notifier.value = ChatMediaDownloadState.downloaded(path);
    }
  }

  /// Returns the local path if this URL is already downloaded and the file
  /// still exists on disk, otherwise null. Self-heals the manifest if a
  /// previously-downloaded file has gone missing (e.g. OS-level cleanup).
  Future<String?> cachedPath(String url) async {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return null;

    await _ensureLoaded();
    final record = _records[trimmed];
    if (record == null) return null;

    final file = File(record.localPath);
    if (await file.exists()) {
      record.lastAccessMs = DateTime.now().millisecondsSinceEpoch;
      unawaited(_persist());
      return record.localPath;
    }

    _records.remove(trimmed);
    unawaited(_persist());
    return null;
  }

  /// Downloads [url] (an original Cloudinary URL) if not already cached,
  /// storing it locally and returning the local file path. Safe to call
  /// concurrently for the same URL from multiple widgets — only one
  /// network download will actually happen.
  Future<String> download({
    required String url,
    required ChatMediaKind kind,
    void Function(double progress)? onProgress,
  }) async {
    final trimmedUrl = url.trim();
    if (trimmedUrl.isEmpty) {
      throw const ChatMediaException('Missing media URL.');
    }

    await _ensureLoaded();

    final existing = _records[trimmedUrl];
    if (existing != null) {
      final file = File(existing.localPath);
      if (await file.exists()) {
        existing.lastAccessMs = DateTime.now().millisecondsSinceEpoch;
        unawaited(_persist());
        _notifierFor(trimmedUrl).value =
            ChatMediaDownloadState.downloaded(existing.localPath);
        return existing.localPath;
      }
      _records.remove(trimmedUrl);
    }

    final inFlight = _inFlight[trimmedUrl];
    if (inFlight != null) return inFlight;

    final future = _downloadInternal(
      url: trimmedUrl,
      kind: kind,
      onProgress: onProgress,
    );
    _inFlight[trimmedUrl] = future;
    try {
      return await future;
    } finally {
      _inFlight.remove(trimmedUrl);
    }
  }

  Future<String> _downloadInternal({
    required String url,
    required ChatMediaKind kind,
    void Function(double progress)? onProgress,
  }) async {
    final notifier = _notifierFor(url);

    final online = await ConnectivityService.instance
        .recheckConnection(timeout: const Duration(seconds: 4));
    if (!online) {
      const message =
          'No internet connection. Connect and try again to download this.';
      notifier.value = const ChatMediaDownloadState.failed(message);
      throw const ChatMediaException(message);
    }

    notifier.value = const ChatMediaDownloadState.downloading(0);

    final dir = await _mediaDirFor(kind);
    final ext = CloudinaryMediaUtils.extensionFor(
      url,
      fallback: kind == ChatMediaKind.image ? 'jpg' : 'm4a',
    );
    final fileName = '${CloudinaryMediaUtils.cacheKeyFor(url)}.$ext';
    final finalPath = '${dir.path}/$fileName';
    final partPath = '$finalPath.part';

    final downloadUrl = kind == ChatMediaKind.image
        ? CloudinaryMediaUtils.imageFullQuality(url)
        : url;

    final cancelToken = CancelToken();
    _cancelTokens[url] = cancelToken;

    try {
      await _dio.download(
        downloadUrl,
        partPath,
        cancelToken: cancelToken,
        onReceiveProgress: (received, total) {
          if (total <= 0) return;
          final p = (received / total).clamp(0.0, 1.0);
          notifier.value = ChatMediaDownloadState.downloading(p.toDouble());
          onProgress?.call(p.toDouble());
        },
      );

      final partFile = File(partPath);
      if (!await partFile.exists()) {
        throw const ChatMediaException('Download did not complete.');
      }

      // Replace any stale final file (e.g. a previous failed attempt that
      // left a same-named file behind) before renaming into place.
      final finalFile = File(finalPath);
      if (await finalFile.exists()) {
        try {
          await finalFile.delete();
        } catch (_) {}
      }
      await partFile.rename(finalPath);

      final size = await File(finalPath).length();
      final now = DateTime.now().millisecondsSinceEpoch;

      int? durationMs;
      if (kind == ChatMediaKind.voice) {
        durationMs = await _probeVoiceDuration(finalPath);
      }

      _records[url] = _CacheRecord(
        url: url,
        kind: kind,
        localPath: finalPath,
        sizeBytes: size,
        downloadedAtMs: now,
        lastAccessMs: now,
        durationMs: durationMs,
      );
      await _persist();

      notifier.value = ChatMediaDownloadState.downloaded(finalPath);
      unawaited(_enforceCacheBudget());
      return finalPath;
    } on DioException catch (e) {
      await _cleanupPartial(partPath);
      if (e.type == DioExceptionType.cancel) {
        notifier.value = const ChatMediaDownloadState.notDownloaded();
        throw const ChatMediaException('Download cancelled.');
      }
      const message =
          'Could not download this media. Check your connection and try again.';
      notifier.value = const ChatMediaDownloadState.failed(message);
      throw const ChatMediaException(message);
    } catch (_) {
      await _cleanupPartial(partPath);
      const message = 'Could not download this media. Please try again.';
      notifier.value = const ChatMediaDownloadState.failed(message);
      throw const ChatMediaException(message);
    } finally {
      _cancelTokens.remove(url);
    }
  }

  /// Cancels an in-progress download for [url], if any. The UI reverts to
  /// the not-downloaded state so the user can retry at will.
  void cancelDownload(String url) {
    final token = _cancelTokens[url.trim()];
    if (token != null && !token.isCancelled) {
      token.cancel('User cancelled download');
    }
  }

  Future<void> _cleanupPartial(String path) async {
    try {
      final f = File(path);
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }

  Future<Directory> _mediaDirFor(ChatMediaKind kind) async {
    final base = await getApplicationDocumentsDirectory();
    final sub = kind == ChatMediaKind.image ? 'images' : 'voice';
    final dir = Directory('${base.path}/chat_media/$sub');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<int?> _probeVoiceDuration(String path) async {
    AudioPlayer? probe;
    try {
      probe = AudioPlayer();
      final d = await probe.setFilePath(path).timeout(
            const Duration(seconds: 6),
          );
      if (d == null || d.inMilliseconds <= 0) return null;
      return d.inMilliseconds;
    } catch (_) {
      // Non-fatal — duration will simply show as unknown until the first
      // playback, at which point ChatAudioPlaybackController learns it.
      return null;
    } finally {
      try {
        await probe?.dispose();
      } catch (_) {}
    }
  }

  /// Best-effort known duration for a downloaded (or not-yet-downloaded)
  /// voice note. Returns null if unknown.
  Future<int?> getVoiceDurationMs(String url) async {
    await _ensureLoaded();
    return _records[url.trim()]?.durationMs;
  }

  /// Persists a duration learned during playback (e.g. discovered by
  /// `ChatAudioPlaybackController` on first play) so future opens of the
  /// same message don't need to re-derive it.
  Future<void> setVoiceDurationMs(String url, int ms) async {
    await _ensureLoaded();
    final record = _records[url.trim()];
    if (record == null || ms <= 0) return;
    record.durationMs = ms;
    await _persist();
  }

  /// Last known playback position for a voice note, for resume-from-position.
  Future<int> getPlaybackPositionMs(String url) async {
    await _ensureLoaded();
    return _records[url.trim()]?.positionMs ?? 0;
  }

  Future<void> setPlaybackPositionMs(String url, int ms) async {
    await _ensureLoaded();
    final record = _records[url.trim()];
    if (record == null) return;
    record.positionMs = ms < 0 ? 0 : ms;
    await _persist();
  }

  /// LRU eviction so the local cache never grows unbounded. Runs
  /// automatically (fire-and-forget) after every successful download.
  Future<void> _enforceCacheBudget() async {
    await _ensureLoaded();

    int total = _records.values.fold(0, (sum, r) => sum + r.sizeBytes);
    if (total <= _maxCacheBytes) return;

    final sorted = _records.values.toList()
      ..sort((a, b) => a.lastAccessMs.compareTo(b.lastAccessMs));

    for (final record in sorted) {
      if (total <= _maxCacheBytes) break;
      try {
        final f = File(record.localPath);
        if (await f.exists()) await f.delete();
      } catch (_) {}
      total -= record.sizeBytes;
      _records.remove(record.url);
      _notifiers[record.url]?.value =
          const ChatMediaDownloadState.notDownloaded();
    }

    await _persist();
  }
}
