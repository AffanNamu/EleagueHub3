import 'dart:convert';

import 'enums.dart';
import 'league_format.dart';
import 'league_settings.dart';

class League {
  final String id;
  final String name;

  /// NEW (Premium Feature: Master League System)
  /// If set, this league is a competition inside a Master League container.
  ///
  /// If empty, the league is a standalone league (backward compatible).
  ///
  /// Firestore: `masterLeagueId` (string)
  final String masterLeagueId;

  /// Optional.
  /// Backward compatible: old stored/remote data may not include it.
  final String description;

  /// OPTIONAL: League main image (hero/cover).
  /// Backward compatible: may be absent in old data.
  final String leagueImageUrl;

  /// OPTIONAL: Sponsor/branding image.
  /// Backward compatible: may be absent in old data.
  final String sponsorImageUrl;

  /// OPTIONAL: Viewer capacity (separate from participants).
  /// 0 means not enabled / not purchased.
  final int viewerCapacity;

  /// OPTIONAL: Coupons for participants enabled at creation time.
  /// Coupons are redeemed on Join League -> Payment screen.
  final bool couponsEnabled;

  /// OPTIONAL: Coupon discount percent for this league.
  /// 0 means coupons not enabled.
  /// 100 means free access.
  final int couponDiscountPercent;

  /// OPTIONAL: How many coupons were purchased/covered during league creation payment.
  /// 0 means not specified / not purchased.
  final int couponCount;

  /// NEW: Whether this league uses home & away matches (each team plays twice).
  ///
  /// Stored at the root of the league document as `homeAwayEnabled`.
  /// Backward compatible: if missing, defaults to false (with best-effort inference from settings).
  final bool homeAwayEnabled;

  final LeagueFormat format;
  final LeaguePrivacy privacy;
  final String region;
  final int maxTeams;
  final String season;

  /// RULES AUTHORITY:
  /// Firebase Auth UID of organizer (server-side authorization uses this).
  /// Backward compatible: may be missing in old records.
  final String organizerUid;

  /// UI/OFFLINE ID:
  /// Short/local id used in older deployments and offline-first local storage.
  /// Backward compatible: old deployments may store a shareId/local id here.
  final String organizerUserId;

  /// Join/invite code (Join ID).
  final String code;

  /// QR payload to encode into QR (stable even offline).
  /// If empty in old data, we auto-derive at runtime (see [qrPayload]).
  final String qrPayloadOverride;

  final LeagueSettings settings;
  final int updatedAtMs;
  final int version;

  const League({
    required this.id,
    required this.name,
    this.masterLeagueId = '',
    this.description = '',
    this.leagueImageUrl = '',
    this.sponsorImageUrl = '',
    this.viewerCapacity = 0,
    this.couponsEnabled = false,
    this.couponDiscountPercent = 0,
    this.couponCount = 0,
    this.homeAwayEnabled = false,
    required this.format,
    required this.privacy,
    required this.region,
    required this.maxTeams,
    required this.season,
    this.organizerUid = '',
    required this.organizerUserId,
    required this.code,
    required this.qrPayloadOverride,
    required this.settings,
    required this.updatedAtMs,
    required this.version,
  });

  bool get isPrivate => privacy == LeaguePrivacy.private;

  bool get isInsideMasterLeague => masterLeagueId.trim().isNotEmpty;

  bool get hasLeagueImage => leagueImageUrl.trim().isNotEmpty;
  bool get hasSponsorImage => sponsorImageUrl.trim().isNotEmpty;
  bool get hasViewerCapacity => viewerCapacity > 0;

  /// Safer coupon detection:
  /// - New data: couponsEnabled && couponCount > 0
  /// - Backward compat: some old records may not have couponCount but have discountPercent.
  bool get hasCoupons => couponsEnabled && (couponCount > 0 || couponDiscountPercent > 0);

  /// Backward compatible: if old leagues have no stored QR payload,
  /// compute a stable payload from [id] + [code].
  String get qrPayload {
    if (qrPayloadOverride.trim().isNotEmpty) return qrPayloadOverride;
    return 'eleaguehub://join?code=$code&id=$id';
  }

  /// IMPORTANT (online-only + rules):
  /// `isPrivate` must be a **bool** on Firestore, not 0/1.
  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{
      'id': id,
      'name': name,

      // Master League System
      // Only include when present; standalone leagues omit the field (backward compatible).
      if (masterLeagueId.trim().isNotEmpty) 'masterLeagueId': masterLeagueId.trim(),

      'description': description,

      // Media (optional)
      'leagueImageUrl': leagueImageUrl,
      'sponsorImageUrl': sponsorImageUrl,

      // Viewer capacity (optional paid add-on)
      'viewerCapacity': viewerCapacity,

      // Coupons (optional paid add-on)
      'couponsEnabled': couponsEnabled,
      'couponDiscountPercent': couponDiscountPercent,
      'couponCount': couponCount,

      // NEW: Home/Away matches toggle
      'homeAwayEnabled': homeAwayEnabled,

      'format': format.index,
      'isPrivate': isPrivate, // bool (not 0/1)
      'region': region,
      'maxTeams': maxTeams,
      'season': season,

      // Identity
      'organizerUid': organizerUid, // Firebase UID authority
      'organizerUserId': organizerUserId, // short/local id for UI/offline

      'code': code,
      'qrPayload': qrPayloadOverride,
      'settings': settings.toMap(),
      'updatedAtMs': updatedAtMs,
      'version': version,
    };

    return map;
  }

  /// Stored locally as a JSON string in SharedPreferences (legacy/offline-first).
  /// Online-only migration: should not be used for domain persistence.
  String toJsonString() => jsonEncode(toJson());

  /// Parse legacy JSON string (best-effort).
  static League fromJsonString(String raw) {
    final map = (jsonDecode(raw) as Map).cast<String, dynamic>();
    return fromRemoteMap(map);
  }

  factory League.fromJson(Map<String, dynamic> json) => fromRemoteMap(json);

  static String _stringFromAny(dynamic v) => (v is String) ? v : '';

  static int _intFromAny(dynamic v, {int fallback = 0}) {
    if (v == null) return fallback;
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v.trim()) ?? fallback;
    return fallback;
  }

  static bool _boolFromAny(dynamic v, {bool fallback = false}) {
    if (v == null) return fallback;
    if (v is bool) return v;
    if (v is int) return v == 1;
    if (v is num) return v.toInt() == 1;
    if (v is String) {
      final s = v.trim().toLowerCase();
      if (s == 'true' || s == '1' || s == 'yes') return true;
      if (s == 'false' || s == '0' || s == 'no') return false;
    }
    return fallback;
  }

  static League fromRemoteMap(Map<String, dynamic> map) {
    // Backward/forward compatible key resolution (some deployments may have used different keys).
    final leagueImageUrl = _stringFromAny(map['leagueImageUrl']).trim().isNotEmpty
        ? _stringFromAny(map['leagueImageUrl'])
        : _stringFromAny(map['leagueImage']).trim().isNotEmpty
            ? _stringFromAny(map['leagueImage'])
            : _stringFromAny(map['imageUrl']).trim().isNotEmpty
                ? _stringFromAny(map['imageUrl'])
                : _stringFromAny(map['logoUrl']);

    final sponsorImageUrl = _stringFromAny(map['sponsorImageUrl']).trim().isNotEmpty
        ? _stringFromAny(map['sponsorImageUrl'])
        : _stringFromAny(map['sponsorImage']).trim().isNotEmpty
            ? _stringFromAny(map['sponsorImage'])
            : _stringFromAny(map['sponsorLogoUrl']).trim().isNotEmpty
                ? _stringFromAny(map['sponsorLogoUrl'])
                : _stringFromAny(map['sponsorUrl']);

    final viewerCapacity = _intFromAny(
      map['viewerCapacity'] ?? map['viewerCount'],
      fallback: 0,
    );

    final couponsEnabled = _boolFromAny(
      map['couponsEnabled'] ?? map['hasCoupons'] ?? map['buyCouponsForParticipants'],
      fallback: false,
    );

    final couponDiscountPercent = _intFromAny(
      map['couponDiscountPercent'] ?? map['couponPercent'] ?? map['couponDiscount'],
      fallback: 0,
    ).clamp(0, 100);

    final couponCount = _intFromAny(
      map['couponCount'] ?? map['couponsPurchased'] ?? map['couponQty'],
      fallback: 0,
    );
    final safeCouponCount = couponCount < 0 ? 0 : couponCount;

    final id = (map['id'] as String?) ?? (map['leagueId'] as String?) ?? '';
    final name = (map['name'] as String?) ?? (map['leagueName'] as String?) ?? '';

    // Master League System (optional)
    final masterLeagueId = _stringFromAny(map['masterLeagueId']).trim();

    // New authoritative organizer UID (Firebase UID)
    String organizerUid = _stringFromAny(map['organizerUid']).trim();

    // Backward compatible organizer id resolution for display/offline id:
    final organizerUserId = (map['organizerUserId'] as String?) ??
        (map['ownerId'] as String?) ??
        (map['organizerId'] as String?) ??
        '';

    // If organizerUid missing but organizerUserId looks like a Firebase UID, treat it as organizerUid.
    if (organizerUid.isEmpty && organizerUserId.trim().length > 20) {
      organizerUid = organizerUserId.trim();
    }

    final isPrivate = _boolFromAny(map['isPrivate'], fallback: false);

    final settingsMap = (map['settings'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
    final settings = LeagueSettings.fromMap(settingsMap);

    final bool homeAwayEnabled = (map.containsKey('homeAwayEnabled') || map.containsKey('homeAndAwayEnabled'))
        ? _boolFromAny(map['homeAwayEnabled'] ?? map['homeAndAwayEnabled'], fallback: false)
        : (settingsMap.containsKey('doubleRoundRobin')
            ? _boolFromAny(settingsMap['doubleRoundRobin'], fallback: false)
            : false);

    return League(
      id: id,
      name: name,
      masterLeagueId: masterLeagueId,
      description: (map['description'] as String?) ?? '',
      leagueImageUrl: leagueImageUrl,
      sponsorImageUrl: sponsorImageUrl,
      viewerCapacity: viewerCapacity,
      couponsEnabled: couponsEnabled,
      couponDiscountPercent: couponDiscountPercent,
      couponCount: safeCouponCount,
      homeAwayEnabled: homeAwayEnabled,
      format: LeagueFormatX.fromInt((map['format'] as num?)?.toInt() ?? 0),
      privacy: isPrivate ? LeaguePrivacy.private : LeaguePrivacy.public,
      region: map['region'] as String? ?? 'Global',
      maxTeams: (map['maxTeams'] as num?)?.toInt() ?? 20,
      season: map['season'] as String? ?? '2026',
      organizerUid: organizerUid,
      organizerUserId: organizerUserId,
      code: map['code'] as String? ?? '',
      qrPayloadOverride: map['qrPayload'] as String? ?? '',
      settings: settings,
      updatedAtMs: (map['updatedAtMs'] as num?)?.toInt() ?? 0,
      version: (map['version'] as num?)?.toInt() ?? 1,
    );
  }

  League copyWith({
    String? id,
    String? name,
    String? masterLeagueId,
    String? description,
    String? leagueImageUrl,
    String? sponsorImageUrl,
    int? viewerCapacity,
    bool? couponsEnabled,
    int? couponDiscountPercent,
    int? couponCount,
    bool? homeAwayEnabled,
    LeagueFormat? format,
    LeaguePrivacy? privacy,
    String? region,
    int? maxTeams,
    String? season,
    String? organizerUid,
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
      masterLeagueId: masterLeagueId ?? this.masterLeagueId,
      description: description ?? this.description,
      leagueImageUrl: leagueImageUrl ?? this.leagueImageUrl,
      sponsorImageUrl: sponsorImageUrl ?? this.sponsorImageUrl,
      viewerCapacity: viewerCapacity ?? this.viewerCapacity,
      couponsEnabled: couponsEnabled ?? this.couponsEnabled,
      couponDiscountPercent: couponDiscountPercent ?? this.couponDiscountPercent,
      couponCount: couponCount ?? this.couponCount,
      homeAwayEnabled: homeAwayEnabled ?? this.homeAwayEnabled,
      format: format ?? this.format,
      privacy: privacy ?? this.privacy,
      region: region ?? this.region,
      maxTeams: maxTeams ?? this.maxTeams,
      season: season ?? this.season,
      organizerUid: organizerUid ?? this.organizerUid,
      organizerUserId: organizerUserId ?? this.organizerUserId,
      code: code ?? this.code,
      qrPayloadOverride: qrPayloadOverride ?? this.qrPayloadOverride,
      settings: settings ?? this.settings,
      updatedAtMs: updatedAtMs ?? this.updatedAtMs,
      version: version ?? this.version,
    );
  }
}
