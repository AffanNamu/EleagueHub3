import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/user_friendly_error.dart';
import '../../../core/services/connectivity_service.dart';
import '../../../core/services/safe_video_picker.dart';
import '../../leagues/models/fixture_match.dart';
import '../data/cloudinary_signed_video_upload_service.dart';
import '../data/highlights_repository_firebase.dart';
import '../data/video_compression_service.dart';

enum HighlightUploadStage {
  idle,
  picking,
  probing,
  preparingDoc,
  compressing,
  uploading,
  finishing,
  done,
  failed,
}

class HighlightUploadState {
  final HighlightUploadStage stage;
  final double progress01;

  /// Human-readable status for UI.
  final String message;

  /// Firestore highlight doc id (stable public id suffix).
  final String? highlightId;

  /// Local compressed file path (best-effort, may be deleted on completion).
  final String? compressedPath;

  /// Match id being uploaded (useful for UI/diagnostics).
  final String? matchId;

  const HighlightUploadState({
    required this.stage,
    required this.progress01,
    required this.message,
    required this.highlightId,
    required this.compressedPath,
    required this.matchId,
  });

  factory HighlightUploadState.idle() => const HighlightUploadState(
        stage: HighlightUploadStage.idle,
        progress01: 0,
        message: '',
        highlightId: null,
        compressedPath: null,
        matchId: null,
      );

  HighlightUploadState copyWith({
    HighlightUploadStage? stage,
    double? progress01,
    String? message,
    String? highlightId,
    String? compressedPath,
    String? matchId,
  }) {
    return HighlightUploadState(
      stage: stage ?? this.stage,
      progress01: progress01 ?? this.progress01,
      message: message ?? this.message,
      highlightId: highlightId ?? this.highlightId,
      compressedPath: compressedPath ?? this.compressedPath,
      matchId: matchId ?? this.matchId,
    );
  }
}

/// NOT autoDispose:
/// - Required for "background upload handling" inside the app.
/// - If user navigates away from MatchDetailScreen, upload continues.
/// - If you want per-session reset, call [HighlightUploadController.reset()].
final highlightUploadControllerProvider =
    StateNotifierProvider<HighlightUploadController, HighlightUploadState>(
  (ref) => HighlightUploadController(
    highlights: HighlightsRepositoryFirebase(),
    compression: VideoCompressionService(),
    cloudinary: CloudinarySignedVideoUploadService(),
  ),
);

class HighlightUploadController extends StateNotifier<HighlightUploadState> {
  HighlightUploadController({
    required HighlightsRepositoryFirebase highlights,
    required VideoCompressionService compression,
    required CloudinarySignedVideoUploadService cloudinary,
    FirebaseAuth? auth,
  })  : _highlights = highlights,
        _compression = compression,
        _cloudinary = cloudinary,
        _auth = auth ?? FirebaseAuth.instance,
        super(HighlightUploadState.idle());

  final HighlightsRepositoryFirebase _highlights;
  final VideoCompressionService _compression;
  final CloudinarySignedVideoUploadService _cloudinary;
  final FirebaseAuth _auth;

  CancelToken? _cancelToken;
  bool _disposed = false;

  bool get isBusy =>
      state.stage != HighlightUploadStage.idle &&
      state.stage != HighlightUploadStage.done &&
      state.stage != HighlightUploadStage.failed;

  void reset() {
    cancel();
    if (_disposed) return;
    state = HighlightUploadState.idle();
  }

  void cancel() {
    _cancelToken?.cancel('User cancelled');
    _cancelToken = null;
  }

  Future<void> uploadHighlightForMatch(FixtureMatch match) async {
    if (isBusy) return;

    final uid = (_auth.currentUser?.uid ?? '').trim();
    if (uid.isEmpty) {
      _set(stage: HighlightUploadStage.failed, message: 'Please sign in and try again.');
      return;
    }

    final matchId = match.id.trim();
    if (matchId.isEmpty) {
      _set(stage: HighlightUploadStage.failed, message: 'Invalid match.');
      return;
    }

    _set(matchId: matchId);

    try {
      _set(stage: HighlightUploadStage.picking, message: 'Select highlight video...', progress01: 0);

      final pick = await SafeVideoPicker.pickVideo();
      if (pick.wasCancelled) {
        _setIdle();
        return;
      }
      if (!pick.isSuccess) {
        _set(stage: HighlightUploadStage.failed, message: pick.errorMessage ?? 'Failed to select video.');
        return;
      }

      final pf = pick.file!;
      final path = (pf.path ?? '').trim();
      if (path.isEmpty) {
        _set(stage: HighlightUploadStage.failed, message: 'Selected video path is not available.');
        return;
      }

      // Network gate (prevents wasted compression if completely offline).
      await ConnectivityService.instance.requireOnline(timeout: const Duration(seconds: 4));

      _set(stage: HighlightUploadStage.probing, message: 'Checking video...', progress01: 0.02);

      // Probe early to enforce duration limit BEFORE creating doc.
      final info = await _compression.probe(path);
      if (info.durationSeconds <= 0) {
        _set(stage: HighlightUploadStage.failed, message: 'Could not read video duration. Please choose a different clip.');
        return;
      }
      if (info.durationSeconds > VideoCompressionService.maxDurationSeconds) {
        _set(
          stage: HighlightUploadStage.failed,
          message:
              'Video is too long (${info.durationSeconds.toStringAsFixed(0)}s). Max is ${VideoCompressionService.maxDurationSeconds}s.',
        );
        return;
      }

      // Create/reuse UPLOADING Firestore doc for optimistic UI.
      _set(stage: HighlightUploadStage.preparingDoc, message: 'Preparing upload...', progress01: 0.05);

      final highlightId = await _highlights.getOrCreateUploadingHighlight(match: match);
      _set(highlightId: highlightId);

      // Compress locally (non-blocking) to enforce 720p/15MB policy BEFORE upload.
      _set(stage: HighlightUploadStage.compressing, message: 'Compressing...', progress01: 0.08);

      final compressed = await _compression.compressHighlight(
        inputPath: path,
        onProgress: (p) {
          // Map 0..1 into 0.08..0.55
          final mapped = 0.08 + (p.clamp(0.0, 1.0) * 0.47);
          _set(progress01: mapped);
        },
      );

      _set(
        compressedPath: compressed.outputPath,
        message: 'Uploading...',
        stage: HighlightUploadStage.uploading,
        progress01: 0.56,
      );

      // Compute folder structure per spec.
      final teamId = await _highlights.requireUploadTeamIdOrThrow(match: match);
      final folder = 'match_highlights/${match.leagueId}/${match.id}/$teamId';

      // Stable publicId suffix = highlightId (idempotent uploads overwrite same Cloudinary asset).
      final publicId = highlightId;

      _cancelToken?.cancel('Replaced');
      _cancelToken = CancelToken();

      final res = await _uploadWithRetry(
        () => _cloudinary.uploadHighlightVideo(
          filePath: compressed.outputPath,
          folder: folder,
          publicId: publicId,
          cancelToken: _cancelToken,
          onProgress: (sent, total) {
            if (total <= 0) return;
            final p = (sent / total).clamp(0.0, 1.0);

            // Map upload progress into 0.56..0.95
            final mapped = 0.56 + (p * 0.39);
            _set(progress01: mapped, message: 'Uploading... ${(p * 100).toStringAsFixed(0)}%');
          },
        ),
      );

      _set(stage: HighlightUploadStage.finishing, message: 'Finalizing...', progress01: 0.96);

      final thumbnailUrl = CloudinarySignedVideoUploadService.buildLightweightThumbnailUrl(
        secureVideoUrl: res.secureUrl,
        width: 480,
        second: 0,
      );

      await _highlights.markUploadSucceeded(
        matchId: match.id,
        highlightId: highlightId,
        cloudinaryPublicId: res.publicId,
        secureUrl: res.secureUrl,
        thumbnailUrl: thumbnailUrl,
        duration: res.duration,
        size: res.bytes,
        format: res.format,
      );

      // Best-effort cleanup of compressed file (saves device storage).
      try {
        final out = File(compressed.outputPath);
        if (await out.exists()) await out.delete();
      } catch (_) {}

      _cancelToken = null;
      _set(stage: HighlightUploadStage.done, message: 'Uploaded', progress01: 1.0);
    } catch (e) {
      _cancelToken = null;

      final err = e is Object ? e : Exception('unknown');
      final msg = _friendly(err);
      _set(stage: HighlightUploadStage.failed, message: msg);

      // Keep doc in UPLOADING state so user can retry without duplicates.
      final hid = state.highlightId;
      if (hid != null && hid.trim().isNotEmpty) {
        try {
          await _highlights.markUploadFailed(matchId: match.id, highlightId: hid);
        } catch (_) {}
      }
    }
  }

  void _setIdle() {
    if (_disposed) return;
    state = HighlightUploadState.idle();
  }

  void _set({
    HighlightUploadStage? stage,
    double? progress01,
    String? message,
    String? highlightId,
    String? compressedPath,
    String? matchId,
  }) {
    if (_disposed) return;
    state = state.copyWith(
      stage: stage,
      progress01: progress01,
      message: message,
      highlightId: highlightId,
      compressedPath: compressedPath,
      matchId: matchId,
    );
  }

  String _friendly(Object e) {
    if (e is UserFriendlyException) return e.message;
    if (e is SocketException) return 'Your network appears to be offline. Please try again.';
    if (e is TimeoutException) return 'Your internet connection seems unstable. Please try again.';
    if (e is DioException && CancelToken.isCancel(e)) return 'Upload cancelled.';
    return UserFriendlyError.toMessage(e);
  }

  bool _isRetryable(Object e) {
    if (e is DioException && CancelToken.isCancel(e)) return false;
    if (e is SocketException) return true;
    if (e is TimeoutException) return true;

    final s = e.toString().toLowerCase();
    if (s.contains('timeout')) return true;
    if (s.contains('network')) return true;
    if (s.contains('unavailable')) return true;

    // Signed endpoint or Cloudinary transient errors often appear as 5xx.
    if (s.contains('upload failed (500)') || s.contains('upload failed (502)') || s.contains('upload failed (503)')) {
      return true;
    }
    return false;
  }

  Future<T> _uploadWithRetry<T>(Future<T> Function() op) async {
    const maxAttempts = 3;
    var attempt = 0;
    var delay = const Duration(seconds: 1);

    while (true) {
      attempt++;
      try {
        return await op().timeout(const Duration(minutes: 2));
      } catch (e) {
        final err = e is Object ? e : Exception('unknown');

        if (err is DioException && CancelToken.isCancel(err)) rethrow;

        if (attempt >= maxAttempts || !_isRetryable(err)) rethrow;

        // Exponential backoff with upper bound to prevent infinite loops.
        await Future<void>.delayed(delay);
        delay = Duration(seconds: (delay.inSeconds * 2).clamp(2, 8));
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _cancelToken?.cancel('Disposed');
    _cancelToken = null;
    super.dispose();
  }
}
