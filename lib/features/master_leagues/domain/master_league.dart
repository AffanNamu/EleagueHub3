import 'package:cloud_firestore/cloud_firestore.dart';

import 'master_league_plan.dart';

enum MasterLeagueStaffRole {
  owner('owner'),
  admin('admin'),
  moderator('moderator');

  const MasterLeagueStaffRole(this.id);

  final String id;

  static MasterLeagueStaffRole? fromString(String? raw) {
    final normalized = (raw ?? '').trim().toLowerCase();
    for (final value in values) {
      if (value.id == normalized) return value;
    }
    return null;
  }
}

enum OrganizerVerificationStatus {
  none('none'),
  pending('pending'),
  approved('approved'),
  rejected('rejected');

  const OrganizerVerificationStatus(this.id);

  final String id;

  static OrganizerVerificationStatus fromString(String? raw) {
    final normalized = (raw ?? '').trim().toLowerCase();
    for (final value in values) {
      if (value.id == normalized) return value;
    }
    return OrganizerVerificationStatus.none;
  }
}

class OrganizerProfile {
  final String bannerUrl;
  final String logoUrl;
  final String bio;
  final Map<String, String> socialLinks;
  final String badge;

  const OrganizerProfile({
    required this.bannerUrl,
    required this.logoUrl,
    required this.bio,
    required this.socialLinks,
    required this.badge,
  });

  const OrganizerProfile.empty()
      : bannerUrl = '',
        logoUrl = '',
        bio = '',
        socialLinks = const <String, String>{},
        badge = '';

  static Map<String, String> _stringMap(dynamic v) {
    if (v is Map) {
      final out = <String, String>{};
      for (final e in v.entries) {
        final k = (e.key ?? '').toString().trim();
        final val = (e.value ?? '').toString().trim();
        if (k.isNotEmpty && val.isNotEmpty) {
          out[k] = val;
        }
      }
      return out;
    }
    return const <String, String>{};
  }

  factory OrganizerProfile.fromMap(Map<String, dynamic> map) {
    return OrganizerProfile(
      bannerUrl: (map['bannerUrl'] as String? ?? '').trim(),
      logoUrl: (map['logoUrl'] as String? ?? '').trim(),
      bio: (map['bio'] as String? ?? '').trim(),
      socialLinks: _stringMap(map['socialLinks']),
      badge: (map['badge'] as String? ?? '').trim(),
    );
  }

  Map<String, dynamic> toFirestoreMap() {
    return <String, dynamic>{
      'bannerUrl': bannerUrl.trim(),
      'logoUrl': logoUrl.trim(),
      'bio': bio.trim(),
      'socialLinks': socialLinks.map((k, v) => MapEntry(k.trim(), v.trim())),
      'badge': badge.trim(),
    };
  }

  OrganizerProfile copyWith({
    String? bannerUrl,
    String? logoUrl,
    String? bio,
    Map<String, String>? socialLinks,
    String? badge,
  }) {
    return OrganizerProfile(
      bannerUrl: bannerUrl ?? this.bannerUrl,
      logoUrl: logoUrl ?? this.logoUrl,
      bio: bio ?? this.bio,
      socialLinks: socialLinks ?? this.socialLinks,
      badge: badge ?? this.badge,
    );
  }
}

class OrganizerAnalytics {
  final int totalTournamentsCreated;
  final int totalParticipantsTeams;
  final int totalMatches;

  const OrganizerAnalytics({
    required this.totalTournamentsCreated,
    required this.totalParticipantsTeams,
    required this.totalMatches,
  });

  const OrganizerAnalytics.empty()
      : totalTournamentsCreated = 0,
        totalParticipantsTeams = 0,
        totalMatches = 0;

  factory OrganizerAnalytics.fromMap(Map<String, dynamic> map) {
    int toInt(dynamic v) {
      if (v is int) return v;
      if (v is num) return v.toInt();
      return 0;
    }

    return OrganizerAnalytics(
      totalTournamentsCreated: toInt(map['totalTournamentsCreated']),
      totalParticipantsTeams: toInt(map['totalParticipantsTeams']),
      totalMatches: toInt(map['totalMatches']),
    );
  }

  Map<String, dynamic> toFirestoreMap() {
    return <String, dynamic>{
      'totalTournamentsCreated': totalTournamentsCreated,
      'totalParticipantsTeams': totalParticipantsTeams,
      'totalMatches': totalMatches,
    };
  }

  OrganizerAnalytics copyWith({
    int? totalTournamentsCreated,
    int? totalParticipantsTeams,
    int? totalMatches,
  }) {
    return OrganizerAnalytics(
      totalTournamentsCreated:
          totalTournamentsCreated ?? this.totalTournamentsCreated,
      totalParticipantsTeams:
          totalParticipantsTeams ?? this.totalParticipantsTeams,
      totalMatches: totalMatches ?? this.totalMatches,
    );
  }
}

class MasterLeagueCompetitionDraft {
  final String name;
  final double entryFee;
  final int maxParticipants;
  final String currency;

  const MasterLeagueCompetitionDraft({
    required this.name,
    required this.entryFee,
    required this.maxParticipants,
    required this.currency,
  });

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'name': name.trim(),
      'entryFee': entryFee,
      'maxParticipants': maxParticipants,
      'currency': currency.trim().toUpperCase(),
    };
  }

  static MasterLeagueCompetitionDraft fromMap(Map<String, dynamic> map) {
    return MasterLeagueCompetitionDraft(
      name: (map['name'] as String? ?? '').trim(),
      entryFee: ((map['entryFee'] as num?) ?? 0).toDouble(),
      maxParticipants: ((map['maxParticipants'] as num?) ?? 0).toInt(),
      currency: (map['currency'] as String? ?? '').trim().toUpperCase(),
    );
  }
}

class MasterLeague {
  final String id;
  final String name;
  final String ownerId;
  final DateTime? createdAt;
  final String purchaseStatus;
  final List<String> memberIds;
  final Map<String, String> roles;
  final Map<String, String> staffShareIds;
  final MasterLeaguePlan plan;
  final OrganizerProfile organizerProfile;
  final OrganizerAnalytics analytics;
  final int updatedAtMs;
  final int followersCount;
  final String createdViaAttemptId;
  final String sourcePaymentId;
  final String sourceReceiptId;
  final MasterLeagueCompetitionDraft? initialCompetition;

  final OrganizerVerificationStatus verificationStatus;
  final bool verifiedBadge;
  final String verificationRequestId;
  final String verificationReceiptId;
  final String verificationPaymentId;
  final String verificationProvider;
  final int verificationRequestedAtMs;
  final int verificationApprovedAtMs;
  final int verificationExpiresAtMs;
  final String verificationReviewedBy;
  final String verificationNote;
  final String verificationRequestType;

  const MasterLeague({
    required this.id,
    required this.name,
    required this.ownerId,
    required this.createdAt,
    required this.purchaseStatus,
    required this.memberIds,
    required this.roles,
    required this.staffShareIds,
    required this.plan,
    required this.organizerProfile,
    required this.analytics,
    required this.updatedAtMs,
    required this.followersCount,
    required this.createdViaAttemptId,
    required this.sourcePaymentId,
    required this.sourceReceiptId,
    required this.initialCompetition,
    required this.verificationStatus,
    required this.verifiedBadge,
    required this.verificationRequestId,
    required this.verificationReceiptId,
    required this.verificationPaymentId,
    required this.verificationProvider,
    required this.verificationRequestedAtMs,
    required this.verificationApprovedAtMs,
    required this.verificationExpiresAtMs,
    required this.verificationReviewedBy,
    required this.verificationNote,
    required this.verificationRequestType,
  });

  bool get isActive => purchaseStatus.trim().toLowerCase() == 'active';

  bool get isVerifiedOrganizer =>
      verifiedBadge ||
      verificationStatus == OrganizerVerificationStatus.approved;

  bool get isVerificationPending =>
      verificationStatus == OrganizerVerificationStatus.pending;

  bool get isVerificationRejected =>
      verificationStatus == OrganizerVerificationStatus.rejected;

  bool get verificationExpired =>
      verificationExpiresAtMs > 0 &&
      verificationExpiresAtMs <= DateTime.now().millisecondsSinceEpoch;

  bool get canRenewVerification =>
      isVerifiedOrganizer || verificationExpired || isVerificationRejected;

  bool get lastVerificationWasRenewal =>
      verificationRequestType.trim().toLowerCase() == 'renewal';

  int get maxLeagues => plan.maxLeagues;
  int get maxTeamsPerLeague => plan.maxTeamsPerLeague;

  String get bannerUrl => organizerProfile.bannerUrl;
  String get logoUrl => organizerProfile.logoUrl;
  String get bio => organizerProfile.bio;
  String get badge => organizerProfile.badge;
  Map<String, String> get socialLinks => organizerProfile.socialLinks;

  int get totalTournamentsCreated => analytics.totalTournamentsCreated;
  int get totalParticipantsTeams => analytics.totalParticipantsTeams;
  int get totalMatches => analytics.totalMatches;

  String roleFor(String uid) {
    final u = uid.trim();
    if (u.isEmpty) return 'none';
    final role = roles[u]?.trim().toLowerCase() ?? '';
    if (role.isNotEmpty) return role;
    if (ownerId.trim() == u) return 'owner';
    if (memberIds.contains(u)) return 'member';
    return 'none';
  }

  MasterLeagueStaffRole? roleEnumFor(String uid) {
    return MasterLeagueStaffRole.fromString(roleFor(uid));
  }

  bool isOwner(String uid) => roleFor(uid) == 'owner';
  bool isAdmin(String uid) => roleFor(uid) == 'admin';
  bool isModerator(String uid) => roleFor(uid) == 'moderator';

  bool canSeeOrganizerProfile(String uid) {
    final role = roleFor(uid);
    return role == 'owner' || role == 'admin' || role == 'moderator';
  }

  bool canViewOrganizerProfile(String uid) => canSeeOrganizerProfile(uid);

  bool canManageStaff(String uid) => isOwner(uid);

  String? staffShareIdFor(String uid) {
    final value = staffShareIds[uid.trim()]?.trim() ?? '';
    return value.isEmpty ? null : value;
  }

  Map<String, dynamic> toFirestoreMap() {
    return <String, dynamic>{
      'name': name.trim(),
      'ownerId': ownerId.trim(),
      if (createdAt != null) 'createdAt': Timestamp.fromDate(createdAt!),
      'purchaseStatus': purchaseStatus.trim(),
      'memberIds': memberIds
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toSet()
          .toList(growable: false),
      'roles': roles.map((k, v) => MapEntry(k.trim(), v.trim())),
      'staffShareIds': staffShareIds.map((k, v) => MapEntry(k.trim(), v.trim())),
      'plan': plan.id,
      'updatedAtMs': updatedAtMs,
      'followersCount': followersCount,
      'createdViaAttemptId': createdViaAttemptId.trim(),
      'sourcePaymentId': sourcePaymentId.trim(),
      'sourceReceiptId': sourceReceiptId.trim(),
      if (initialCompetition != null)
        'initialCompetition': initialCompetition!.toMap(),
      'verificationStatus': verificationStatus.id,
      'verifiedBadge': verifiedBadge,
      'verificationRequestId': verificationRequestId.trim(),
      'verificationReceiptId': verificationReceiptId.trim(),
      'verificationPaymentId': verificationPaymentId.trim(),
      'verificationProvider': verificationProvider.trim(),
      'verificationRequestedAtMs': verificationRequestedAtMs,
      'verificationApprovedAtMs': verificationApprovedAtMs,
      'verificationExpiresAtMs': verificationExpiresAtMs,
      'verificationReviewedBy': verificationReviewedBy.trim(),
      'verificationNote': verificationNote.trim(),
      'verificationRequestType': verificationRequestType.trim(),
      ...organizerProfile.toFirestoreMap(),
      ...analytics.toFirestoreMap(),
    };
  }

  static MasterLeague fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = (doc.data() ?? <String, dynamic>{}).cast<String, dynamic>();
    return fromMap(doc.id, data);
  }

  static Map<String, String> _stringMap(dynamic v) {
    if (v is Map) {
      final out = <String, String>{};
      for (final e in v.entries) {
        final k = (e.key ?? '').toString().trim();
        final val = (e.value ?? '').toString().trim();
        if (k.isNotEmpty && val.isNotEmpty) {
          out[k] = val;
        }
      }
      return out;
    }
    return const <String, String>{};
  }

  static List<String> _stringList(dynamic v) {
    if (v is! List) return const <String>[];
    final out = <String>[];
    for (final item in v) {
      final value = item is String ? item.trim() : '';
      if (value.isNotEmpty && !out.contains(value)) {
        out.add(value);
      }
    }
    return List<String>.unmodifiable(out);
  }

  static int _toInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return 0;
  }

  static bool _toBool(dynamic v) {
    if (v is bool) return v;
    if (v is num) return v.toInt() == 1;
    if (v is String) {
      final s = v.trim().toLowerCase();
      return s == 'true' || s == '1' || s == 'yes';
    }
    return false;
  }

  static DateTime? _toDateTime(dynamic v) {
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    if (v is int) return DateTime.fromMillisecondsSinceEpoch(v);
    if (v is num) return DateTime.fromMillisecondsSinceEpoch(v.toInt());
    return null;
  }

  static MasterLeague fromMap(String id, Map<String, dynamic> map) {
    final ownerId =
        ((map['ownerId'] as String?) ?? (map['ownerUid'] as String?) ?? '').trim();

    final members = _stringList(map['memberIds']);
    final normalizedMembers = <String>[
      ...members,
      if (ownerId.isNotEmpty && !members.contains(ownerId)) ownerId,
    ];

    final roleMap = _stringMap(map['roles']);
    final normalizedRoles = <String, String>{
      ...roleMap,
      if (ownerId.isNotEmpty) ownerId: 'owner',
    };

    final staffShareIds = _stringMap(map['staffShareIds']);

    final organizerProfileMap = map['organizerProfile'];
    final organizerProfile = organizerProfileMap is Map
        ? OrganizerProfile.fromMap(
            organizerProfileMap.cast<String, dynamic>(),
          ).copyWith(
            bannerUrl: (organizerProfileMap['bannerUrl'] as String?)
                        ?.trim()
                        .isNotEmpty ==
                    true
                ? (organizerProfileMap['bannerUrl'] as String?)!.trim()
                : ((map['bannerUrl'] as String?) ?? '').trim(),
            logoUrl:
                (organizerProfileMap['logoUrl'] as String?)?.trim().isNotEmpty ==
                        true
                    ? (organizerProfileMap['logoUrl'] as String?)!.trim()
                    : ((map['logoUrl'] as String?) ?? '').trim(),
            bio: (organizerProfileMap['bio'] as String?)?.trim().isNotEmpty ==
                    true
                ? (organizerProfileMap['bio'] as String?)!.trim()
                : ((map['bio'] as String?) ?? '').trim(),
            badge:
                (organizerProfileMap['badge'] as String?)?.trim().isNotEmpty ==
                        true
                    ? (organizerProfileMap['badge'] as String?)!.trim()
                    : ((map['badge'] as String?) ?? '').trim(),
            socialLinks: _stringMap(organizerProfileMap['socialLinks']).isNotEmpty
                ? _stringMap(organizerProfileMap['socialLinks'])
                : _stringMap(map['socialLinks']),
          )
        : OrganizerProfile(
            bannerUrl: (map['bannerUrl'] as String? ?? '').trim(),
            logoUrl: (map['logoUrl'] as String? ?? '').trim(),
            bio: (map['bio'] as String? ?? '').trim(),
            socialLinks: _stringMap(map['socialLinks']),
            badge: (map['badge'] as String? ?? '').trim(),
          );

    final analyticsMap = map['analytics'];
    final analytics = analyticsMap is Map
        ? OrganizerAnalytics.fromMap(
            <String, dynamic>{
              'totalTournamentsCreated':
                  analyticsMap['totalTournamentsCreated'] ??
                      map['totalTournamentsCreated'],
              'totalParticipantsTeams':
                  analyticsMap['totalParticipantsTeams'] ??
                      map['totalParticipantsTeams'],
              'totalMatches':
                  analyticsMap['totalMatches'] ?? map['totalMatches'],
            },
          )
        : OrganizerAnalytics(
            totalTournamentsCreated: _toInt(map['totalTournamentsCreated']),
            totalParticipantsTeams: _toInt(map['totalParticipantsTeams']),
            totalMatches: _toInt(map['totalMatches']),
          );

    final initialCompetitionMap = map['initialCompetition'];
    final initialCompetition = initialCompetitionMap is Map
        ? MasterLeagueCompetitionDraft.fromMap(
            initialCompetitionMap.cast<String, dynamic>(),
          )
        : null;

    return MasterLeague(
      id: id.trim(),
      name: (map['name'] as String? ?? '').trim(),
      ownerId: ownerId,
      createdAt: _toDateTime(map['createdAt']),
      purchaseStatus: (map['purchaseStatus'] as String? ?? 'active').trim(),
      memberIds: List<String>.unmodifiable(normalizedMembers),
      roles: Map<String, String>.unmodifiable(normalizedRoles),
      staffShareIds: Map<String, String>.unmodifiable(staffShareIds),
      plan: MasterLeaguePlan.fromString(map['plan'] as String?),
      organizerProfile: organizerProfile,
      analytics: analytics,
      updatedAtMs: _toInt(map['updatedAtMs']),
      followersCount: _toInt(map['followersCount']),
      createdViaAttemptId: (map['createdViaAttemptId'] as String? ?? '').trim(),
      sourcePaymentId: (map['sourcePaymentId'] as String? ?? '').trim(),
      sourceReceiptId: (map['sourceReceiptId'] as String? ?? '').trim(),
      initialCompetition: initialCompetition,
      verificationStatus: OrganizerVerificationStatus.fromString(
        map['verificationStatus'] as String?,
      ),
      verifiedBadge: _toBool(map['verifiedBadge']),
      verificationRequestId:
          (map['verificationRequestId'] as String? ?? '').trim(),
      verificationReceiptId:
          (map['verificationReceiptId'] as String? ?? '').trim(),
      verificationPaymentId:
          (map['verificationPaymentId'] as String? ?? '').trim(),
      verificationProvider:
          (map['verificationProvider'] as String? ?? '').trim(),
      verificationRequestedAtMs: _toInt(map['verificationRequestedAtMs']),
      verificationApprovedAtMs: _toInt(map['verificationApprovedAtMs']),
      verificationExpiresAtMs: _toInt(map['verificationExpiresAtMs']),
      verificationReviewedBy:
          (map['verificationReviewedBy'] as String? ?? '').trim(),
      verificationNote: (map['verificationNote'] as String? ?? '').trim(),
      verificationRequestType:
          (map['verificationRequestType'] as String? ?? 'initial').trim(),
    );
  }

  MasterLeague copyWith({
    String? id,
    String? name,
    String? ownerId,
    DateTime? createdAt,
    String? purchaseStatus,
    List<String>? memberIds,
    Map<String, String>? roles,
    Map<String, String>? staffShareIds,
    MasterLeaguePlan? plan,
    OrganizerProfile? organizerProfile,
    OrganizerAnalytics? analytics,
    int? updatedAtMs,
    int? followersCount,
    String? createdViaAttemptId,
    String? sourcePaymentId,
    String? sourceReceiptId,
    MasterLeagueCompetitionDraft? initialCompetition,
    OrganizerVerificationStatus? verificationStatus,
    bool? verifiedBadge,
    String? verificationRequestId,
    String? verificationReceiptId,
    String? verificationPaymentId,
    String? verificationProvider,
    int? verificationRequestedAtMs,
    int? verificationApprovedAtMs,
    int? verificationExpiresAtMs,
    String? verificationReviewedBy,
    String? verificationNote,
    String? verificationRequestType,
  }) {
    return MasterLeague(
      id: id ?? this.id,
      name: name ?? this.name,
      ownerId: ownerId ?? this.ownerId,
      createdAt: createdAt ?? this.createdAt,
      purchaseStatus: purchaseStatus ?? this.purchaseStatus,
      memberIds: memberIds ?? this.memberIds,
      roles: roles ?? this.roles,
      staffShareIds: staffShareIds ?? this.staffShareIds,
      plan: plan ?? this.plan,
      organizerProfile: organizerProfile ?? this.organizerProfile,
      analytics: analytics ?? this.analytics,
      updatedAtMs: updatedAtMs ?? this.updatedAtMs,
      followersCount: followersCount ?? this.followersCount,
      createdViaAttemptId: createdViaAttemptId ?? this.createdViaAttemptId,
      sourcePaymentId: sourcePaymentId ?? this.sourcePaymentId,
      sourceReceiptId: sourceReceiptId ?? this.sourceReceiptId,
      initialCompetition: initialCompetition ?? this.initialCompetition,
      verificationStatus: verificationStatus ?? this.verificationStatus,
      verifiedBadge: verifiedBadge ?? this.verifiedBadge,
      verificationRequestId: verificationRequestId ?? this.verificationRequestId,
      verificationReceiptId:
          verificationReceiptId ?? this.verificationReceiptId,
      verificationPaymentId:
          verificationPaymentId ?? this.verificationPaymentId,
      verificationProvider: verificationProvider ?? this.verificationProvider,
      verificationRequestedAtMs:
          verificationRequestedAtMs ?? this.verificationRequestedAtMs,
      verificationApprovedAtMs:
          verificationApprovedAtMs ?? this.verificationApprovedAtMs,
      verificationExpiresAtMs:
          verificationExpiresAtMs ?? this.verificationExpiresAtMs,
      verificationReviewedBy:
          verificationReviewedBy ?? this.verificationReviewedBy,
      verificationNote: verificationNote ?? this.verificationNote,
      verificationRequestType:
          verificationRequestType ?? this.verificationRequestType,
    );
  }
}
