
import 'dart:convert';



import 'enums.dart';

import 'league_format.dart';

import 'league_settings.dart';



class League {

  final String id;

  final String name;



  /// Optional.

  /// Backward compatible: old stored/remote data may not include it.

  final String description;



  final LeagueFormat format;

  final LeaguePrivacy privacy;

  final String region;

  final int maxTeams;

  final String season;



  /// Owner/organiser user id (admin/owner)

  final String organizerUserId;



  /// Join/invite code (Join ID).

  /// Must be generated even offline.

  final String code;



  /// QR payload to encode into QR (stable even offline).

  /// Example payload: "eleaguehub://join?code=ABC123&id=<leagueId>"

  /// If empty in old data, we auto-derive at runtime (see [qrPayload]).

  final String qrPayloadOverride;



  final LeagueSettings settings;

  final int updatedAtMs;

  final int version;



  const League({

    required this.id,

    required this.name,

    this.description = '',

    required this.format,

    required this.privacy,

    required this.region,

    required this.maxTeams,

    required this.season,

    required this.organizerUserId,

    required this.code,

    required this.qrPayloadOverride,

    required this.settings,

    required this.updatedAtMs,

    required this.version,

  });



  bool get isPrivate => privacy == LeaguePrivacy.private;



  /// Backward compatible: if old leagues have no stored QR payload,

  /// compute a stable payload from [id] + [code].

  String get qrPayload {

    if (qrPayloadOverride.trim().isNotEmpty) return qrPayloadOverride;

    return 'eleaguehub://join?code=$code&id=$id';

  }



  Map<String, dynamic> toJson() => {

        'id': id,

        'name': name,

        'description': description,

        'format': format.index,

        'isPrivate': isPrivate ? 1 : 0,

        'region': region,

        'maxTeams': maxTeams,

        'season': season,

        'organizerUserId': organizerUserId,

        'code': code,

        'qrPayload': qrPayloadOverride,

        'settings': settings.toMap(),

        'updatedAtMs': updatedAtMs,

        'version': version,

      };



  /// Stored locally as a JSON string in SharedPreferences

  String toJsonString() => jsonEncode(toJson());



  /// Parse local stored JSON string

  static League fromJsonString(String raw) {

    final map = (jsonDecode(raw) as Map).cast<String, dynamic>();

    return fromRemoteMap(map);

  }



  factory League.fromJson(Map<String, dynamic> json) => fromRemoteMap(json);



  static League fromRemoteMap(Map<String, dynamic> map) {

    return League(

      id: (map['id'] as String?) ?? '',

      name: (map['name'] as String?) ?? '',

      description: (map['description'] as String?) ?? '',

      format: LeagueFormatX.fromInt((map['format'] as num?)?.toInt() ?? 0),

      privacy: (map['isPrivate'] == 1 || map['isPrivate'] == true) ? LeaguePrivacy.private : LeaguePrivacy.public,

      region: map['region'] as String? ?? 'Global',

      maxTeams: (map['maxTeams'] as num?)?.toInt() ?? 20,

      season: map['season'] as String? ?? '2026',

      organizerUserId: map['organizerUserId'] as String? ?? '',

      code: map['code'] as String? ?? '',

      qrPayloadOverride: map['qrPayload'] as String? ?? '',

      settings: LeagueSettings.fromMap((map['settings'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{}),

      updatedAtMs: (map['updatedAtMs'] as num?)?.toInt() ?? 0,

      version: (map['version'] as num?)?.toInt() ?? 1,

    );

  }



  League copyWith({

    String? id,

    String? name,

    String? description,

    LeagueFormat? format,

    LeaguePrivacy? privacy,

    String? region,

    int? maxTeams,

    String? season,

    String? organizerUserId,

    String? code,

    String? qrPayloadOverride,

    LeagueSettings? settings,

    int? updatedAtMs,

    int? version,

  }) {

    return League(

      id: id ?? this.id,

      name: name ?? this.name,

      description: description ?? this.description,

      format: format ?? this.format,

      privacy: privacy ?? this.privacy,

      region: region ?? this.region,

      maxTeams: maxTeams ?? this.maxTeams,

      season: season ?? this.season,

      organizerUserId: organizerUserId ?? this.organizerUserId,

      code: code ?? this.code,

      qrPayloadOverride: qrPayloadOverride ?? this.qrPayloadOverride,

      settings: settings ?? this.settings,

      updatedAtMs: updatedAtMs ?? this.updatedAtMs,

      version: version ?? this.version,

    );

  }

}

