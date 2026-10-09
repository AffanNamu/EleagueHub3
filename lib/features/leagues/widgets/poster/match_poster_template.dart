// lib/features/leagues/widgets/poster/match_poster_template.dart
//
// The extensible template contract (Section 24 of the brief). Each
// template receives the same MatchPosterData + MatchPosterFormat and is
// responsible for its own composition -- but all of them lean on the
// shared primitives in match_poster_kit.dart rather than reimplementing
// team visuals/VS badges/chips from scratch.

import 'package:flutter/material.dart';

import '../../models/match_poster_data.dart';

abstract class MatchPosterTemplate {
  const MatchPosterTemplate();

  /// Stable id, used for selection state and (if ever persisted) storage.
  String get id;

  /// Display name shown in the template picker.
  String get name;

  /// Single emoji shown next to [name] in the template picker.
  String get emoji;

  Widget build(BuildContext context, MatchPosterData data, MatchPosterFormat format);
}

/// Layout knobs derived from the chosen export format. Templates read these
/// instead of hand-rolling their own format checks, so "responsive per
/// format, not just stretched" (Section 14) is consistent across all of
/// them.
class PosterLayoutMetrics {
  const PosterLayoutMetrics._({
    required this.format,
    required this.scale,
    required this.isSquare,
    required this.isTall,
    required this.teamVisualSize,
    required this.vsSize,
  });

  factory PosterLayoutMetrics.forFormat(MatchPosterFormat format, double width) {
    const designWidth = 1080.0;
    final scale = width / designWidth;
    final isSquare = format == MatchPosterFormat.square;
    final isTall = format == MatchPosterFormat.story;

    // Square has less vertical room per unit of width, so team visuals
    // shrink a bit to keep headroom for text; story has the most vertical
    // room, so visuals can be the largest.
    final teamVisualSize = (isSquare ? 230.0 : (isTall ? 300.0 : 270.0)) * scale;
    final vsSize = (isSquare ? 72.0 : 84.0) * scale;

    return PosterLayoutMetrics._(
      format: format,
      scale: scale,
      isSquare: isSquare,
      isTall: isTall,
      teamVisualSize: teamVisualSize,
      vsSize: vsSize,
    );
  }

  final MatchPosterFormat format;
  final double scale;
  final bool isSquare;
  final bool isTall;
  final double teamVisualSize;
  final double vsSize;
}
