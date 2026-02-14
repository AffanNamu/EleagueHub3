import 'package:flutter/foundation.dart';

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
      'startedAtMs': createdAtMs,
      'endedAtMs': endedAtMs,
    };
  }

  Map<String, dynamic> toMap() => toJson();

  factory LeagueSpace.fromJson(Map<String, dynamic> json) {
    return LeagueSpace(
      id: json['id'] as String? ?? '',
      leagueId: json['leagueId'] as String? ?? '',
      hostUserId: json['hostUserId'] as String? ?? '',
      title: json['title'] as String?,
      isLive: json['isLive'] as bool? ?? false,
      createdAtMs: _intFrom(json['createdAtMs'] ?? json['startedAtMs']),
      endedAtMs: json['endedAtMs'] != null ? _intFrom(json['endedAtMs']) : null,
    );
  }

  factory LeagueSpace.fromMap(Map<String, dynamic> map) => LeagueSpace.fromJson(map);

  static int _intFrom(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? 0;
    return 0;
  }
}
