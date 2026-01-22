import 'package:flutter/foundation.dart';

/// Simple per-league audio room ("space") model.
@immutable
class LeagueSpace {
  final String id;
  final String leagueId;
  final String hostUserId;
  final String? title;
  final bool isLive;
  final int createdAtMs;
  final int? endedAtMs;

  const LeagueSpace({
    required this.id,
    required this.leagueId,
    required this.hostUserId,
    required this.title,
    required this.isLive,
    required this.createdAtMs,
    this.endedAtMs,
  });

  LeagueSpace copyWith({
    String? id,
    String? leagueId,
    String? hostUserId,
    String? title,
    bool? isLive,
    int? createdAtMs,
    int? endedAtMs,
  }) {
    return LeagueSpace(
      id: id ?? this.id,
      leagueId: leagueId ?? this.leagueId,
      hostUserId: hostUserId ?? this.hostUserId,
      title: title ?? this.title,
      isLive: isLive ?? this.isLive,
      createdAtMs: createdAtMs ?? this.createdAtMs,
      endedAtMs: endedAtMs ?? this.endedAtMs,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'leagueId': leagueId,
      'hostUserId': hostUserId,
      'title': title,
      'isLive': isLive,
      'createdAtMs': createdAtMs,
      'endedAtMs': endedAtMs,
    };
  }

  factory LeagueSpace.fromJson(Map<String, dynamic> json) {
    return LeagueSpace(
      id: json['id'] as String,
      leagueId: json['leagueId'] as String,
      hostUserId: json['hostUserId'] as String,
      title: json['title'] as String?,
      isLive: json['isLive'] as bool? ?? false,
      createdAtMs: json['createdAtMs'] as int? ?? 0,
      endedAtMs: json['endedAtMs'] as int?,
    );
  }
}
