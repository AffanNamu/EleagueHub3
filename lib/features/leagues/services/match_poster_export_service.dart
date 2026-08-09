// lib/features/leagues/services/match_poster_export_service.dart
//
// Handles turning the on-screen MatchPosterWidget into a shareable,
// high-resolution PNG.
//
// TECHNICAL APPROACH (see implementation report):
// RenderRepaintBoundary.toImage(pixelRatio: ...) — chosen over Canvas
// hand-drawing or a third-party image-composition package because:
//   - It reuses the exact same widget tree already used for the on-screen
//     preview (zero risk of preview/export drifting apart).
//   - `pixelRatio` lets us export at a resolution independent of whatever
//     logical size the preview box happens to be on screen, satisfying the
//     "export should not be a low-res screenshot" requirement.
//   - No new dependency: RenderRepaintBoundary is core Flutter.
//
// Remote images (team badges, competition logo) are precached before
// capture so the export never contains a loading spinner or blank circle.

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class MatchPosterExportException implements Exception {
  final String message;
  const MatchPosterExportException(this.message);

  @override
  String toString() => message;
}

class MatchPosterExportService {
  /// Caps how aggressively we upscale from the on-screen preview size, so
  /// a tiny preview box on a low-end device can't be asked to render an
  /// absurdly large bitmap and blow the memory budget (Section 20).
  static const double _maxPixelRatio = 5.0;

  /// Precaches every remote image so the RepaintBoundary capture doesn't
  /// grab a loading placeholder. Failures are swallowed — the poster
  /// widget already has its own fallback icon per image, so a failed
  /// precache just means that fallback gets exported instead of crashing
  /// the whole flow (Section 19).
  Future<void> precacheImages(BuildContext context, List<String> urls) async {
    for (final raw in urls) {
      final url = raw.trim();
      if (url.isEmpty) continue;
      if (!(url.startsWith('http://') || url.startsWith('https://'))) continue;
      try {
        await precacheImage(NetworkImage(url), context)
            .timeout(const Duration(seconds: 12));
      } catch (_) {
        // Swallowed intentionally — see doc comment above.
      }
    }
  }

  /// Captures whatever is under [repaintBoundaryKey] and re-renders it at
  /// a resolution matching [targetWidth]x[targetHeight] (the chosen export
  /// format), regardless of how large that widget currently is on screen.
  Future<Uint8List> capturePng({
    required GlobalKey repaintBoundaryKey,
    required int targetWidth,
    required int targetHeight,
  }) async {
    final ctx = repaintBoundaryKey.currentContext;
    if (ctx == null) {
      throw const MatchPosterExportException(
        'The poster is not ready yet. Please try again.',
      );
    }

    final renderObject = ctx.findRenderObject();
    if (renderObject is! RenderRepaintBoundary) {
      throw const MatchPosterExportException(
        'The poster is not ready yet. Please try again.',
      );
    }

    if (renderObject.debugNeedsPaint) {
      await Future.delayed(const Duration(milliseconds: 60));
    }

    final currentWidth = renderObject.size.width;
    if (currentWidth <= 0) {
      throw const MatchPosterExportException(
        'The poster could not be measured. Please try again.',
      );
    }

    double pixelRatio = targetWidth / currentWidth;
    if (pixelRatio.isNaN || pixelRatio.isInfinite || pixelRatio <= 0) {
      pixelRatio = 1;
    }
    if (pixelRatio > _maxPixelRatio) pixelRatio = _maxPixelRatio;

    try {
      final image = await renderObject.toImage(pixelRatio: pixelRatio);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();

      if (byteData == null) {
        throw const MatchPosterExportException(
          'Could not encode the poster image.',
        );
      }

      return byteData.buffer.asUint8List();
    } on MatchPosterExportException {
      rethrow;
    } catch (e) {
      throw MatchPosterExportException(
        'Could not export the poster: ${e.toString()}',
      );
    }
  }

  Future<File> saveToTempFile(
    Uint8List bytes, {
    String filenamePrefix = 'esportlyic_match_poster',
  }) async {
    try {
      final dir = await getTemporaryDirectory();
      final ts = DateTime.now().millisecondsSinceEpoch;
      final file = File('${dir.path}/${filenamePrefix}_$ts.png');
      await file.writeAsBytes(bytes, flush: true);
      return file;
    } catch (e) {
      throw MatchPosterExportException(
        'Could not save the poster image: ${e.toString()}',
      );
    }
  }

  /// Opens the native share sheet (WhatsApp, Instagram, Telegram, Files,
  /// Save Image, etc). Used for both "Share" and "Save" — on both Android
  /// and iOS the system share sheet includes a save-to-device target, so
  /// this avoids adding a gallery-saving dependency just for that.
  Future<void> shareFile(File file, {String? text}) async {
    try {
      await Share.shareXFiles([XFile(file.path)], text: text);
    } catch (e) {
      throw MatchPosterExportException(
        'Could not open the share sheet: ${e.toString()}',
      );
    }
  }

  Future<void> deleteQuietly(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {
      // Best-effort cleanup only.
    }
  }
}
