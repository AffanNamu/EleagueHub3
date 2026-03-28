import 'package:cloud_firestore/cloud_firestore.dart';

import 'master_league_plan.dart';

class MasterLeagueCompetitionDraft {
  const MasterLeagueCompetitionDraft({
    required this.name,
    required this.entryFee,
    required this.maxParticipants,
    required this.currency,
  });

  final String name;
  final double entryFee;
  final int maxParticipants;
  final String currency;

  factory MasterLeagueCompetitionDraft.fromMap(Map<String, dynamic> map) {
    final entryFeeRaw = map['entryFee'];
    final maxRaw = map['maxParticipants'];

    return MasterLeagueCompetitionDraft(
      name: (map['name'] as String? ?? '').trim(),
      entryFee: entryFeeRaw is num ? entryFeeRaw.toDouble() : 0,
      maxParticipants: maxRaw is num ? maxRaw.toInt() : 0,
      currency: (map['currency'] as String? ?? '').trim(),
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'name': name.trim(),
      'entryFee': entryFee,
      'maxParticipants': maxParticipants,
      'currency': currency.trim(),
    };
  }

  String get rewardsPlan {
    final value = currency.trim();
    if (value.isEmpty || value.toUpperCase() == 'NONE') {
      return 'No rewards specified yet';
    }
    return value;
  }

  bool get hasRewardsPlan {
    final value = currency.trim();
    return value.isNotEmpty && value.toUpperCase() != 'NONE';
  }
}

class OrganizerProfile {
  const OrganizerProfile({
    required this.bannerUrl,
    required this.logoUrl,
    required this.bio,
    required this.socialLinks,
    required this.badge,
  });

  final String bannerUrl;
  final String logoUrl;
  final String bio;
  final Map<String, String> socialLinks;
  final String badge;

  factory OrganizerProfile.empty() {
    return const OrganizerProfile(
      bannerUrl: '',
      logoUrl: '',
      bio: '',
      socialLinks: <String, String>{},
      badge: '',
    );
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
      socialLinks: socialLinks ?? Map<String, String>.from(this.socialLinks),
      badge: badge ?? this.badge,
    );
  }

  factory OrganizerProfile.fromRootMap(Map<String, dynamic> map) {
    final linksRaw = map['socialLinks'];
    final links = <String, String>{};

    if (linksRaw is Map) {
      for (final entry in linksRaw.entries) {
        final k = entry.key.toString().trim();
        final v = entry.value?.toString().trim() ?? '';
        if (k.isNotEmpty && v.isNotEmpty) {
          links[k] = v;
        }
      }
    }

    return OrganizerProfile(
      bannerUrl: (map['bannerUrl'] as String? ?? '').trim(),
      logoUrl: (map['logoUrl'] as String? ?? '').trim(),
      bio: (map['bio'] as String? ?? '').trim(),
      socialLinks: Map<String, String>.from(links),
      badge: (map['badge'] as String? ?? '').trim(),
    );
  }
}

class MasterLeagueAnalytics {
  const MasterLeagueAnalytics({
    required this.totalTournamentsCreated,
    required this.totalParticipantsTeams,
    required this.totalMatches,
  });

  final int totalTournamentsCreated;
  final int totalParticipantsTeams;
  final int totalMatches;

  factory MasterLeagueAnalytics.fromRootMap(Map<String, dynamic> map) {
    int asInt(dynamic v) {
      if (v is int) return v;
      if (v is num) return v.toInt();
      return 0;
    }

    return MasterLeagueAnalytics(
      totalTournamentsCreated: asInt(map['totalTournamentsCreated']),
      totalParticipantsTeams: asInt(map['totalParticipantsTeams']),
      totalMatches: asInt(map['totalMatches']),
    );
  }
}

MasterLeaguePlan _planFromId(String id) {
  final clean = id.trim().toLowerCase();
  for (final plan in MasterLeaguePlan.values) {
    if (plan.id.trim().toLowerCase() == clean) return plan;
  }
  return MasterLeaguePlan.basic;
}

class MasterLeague {
  const MasterLeague({
    required this.id,
    required this.name,
    required this.ownerId,
    required this.memberIds,
    required this.roles,
    required this.updatedAtMs,
    required this.plan,
    required this.createdAt,
    required this.purchaseStatus,
    required this.organizerProfile,
    required this.analytics,
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

  final String id;
  final String name;
  final String ownerId;
  final List<String> memberIds;
  final Map<String, String> roles;
  final int updatedAtMs;
  final MasterLeaguePlan plan;
  final Timestamp? createdAt;
  final String purchaseStatus;
  final OrganizerProfile organizerProfile;
  final MasterLeagueAnalytics analytics;
  final int followersCount;
  final String createdViaAttemptId;
  final String sourcePaymentId;
  final String sourceReceiptId;
  final MasterLeagueCompetitionDraft? initialCompetition;
  final String verificationStatus;
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

  static int _asInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return 0;
  }

  static bool _asBool(dynamic v) {
    if (v is bool) return v;
    if (v is num) return v != 0;
    if (v is String) {
      final s = v.trim().toLowerCase();
      return s == 'true' || s == '1' || s == 'yes';
    }
    return false;
  }

  static List<String> _asStringList(dynamic v) {
    if (v is List) {
      return v
          .map((e) => e?.toString().trim() ?? '')
          .where((e) => e.isNotEmpty)
          .toList(growable: false);
    }
    return const <String>[];
  }

  static Map<String, String> _asStringMap(dynamic v) {
    final out = <String, String>{};
    if (v is Map) {
      for (final entry in v.entries) {
        final k = entry.key.toString().trim();
        final val = entry.value?.toString().trim() ?? '';
        if (k.isNotEmpty && val.isNotEmpty) {
          out[k] = val;
        }
      }
    }
    return out;
  }

  static String _readOwnerId(Map<String, dynamic> map) {
    final ownerId = (map['ownerId'] as String? ?? '').trim();
    if (ownerId.isNotEmpty) return ownerId;

    final ownerUid = (map['ownerUid'] as String? ?? '').trim();
    if (ownerUid.isNotEmpty) return ownerUid;

    final organizerUid = (map['organizerUid'] as String? ?? '').trim();
    if (organizerUid.isNotEmpty) return organizerUid;

    final organizerUserId = (map['organizerUserId'] as String? ?? '').trim();
    if (organizerUserId.isNotEmpty) return organizerUserId;

    return '';
  }

  static List<String> _readMemberIds(Map<String, dynamic> map, String ownerId) {
    final members = _asStringList(map['memberIds']).toSet();

    if (members.isEmpty) {
      final rolesMap = _asStringMap(map['roles']);
      members.addAll(rolesMap.keys.where((e) => e.trim().isNotEmpty));
    }

    if (ownerId.isNotEmpty) {
      members.add(ownerId);
    }

    return members.toList(growable: false);
  }

  static Map<String, String> _readRoles(Map<String, dynamic> map, String ownerId) {
    final roles = _asStringMap(map['roles']);
    if (ownerId.isNotEmpty && !roles.containsKey(ownerId)) {
      roles[ownerId] = 'owner';
    }
    return roles;
  }

  factory MasterLeague.fromMap(String id, Map<String, dynamic> map) {
    final ownerId = _readOwnerId(map);
    final planId = (map['plan'] as String? ?? 'basic').trim();
    final initialRaw = map['initialCompetition'];

    return MasterLeague(
      id: id.trim(),
      name: (map['name'] as String? ?? '').trim(),
      ownerId: ownerId,
      memberIds: List<String>.from(_readMemberIds(map, ownerId)),
      roles: Map<String, String>.from(_readRoles(map, ownerId)),
      updatedAtMs: _asInt(map['updatedAtMs']),
      plan: _planFromId(planId),
      createdAt: map['createdAt'] is Timestamp ? map['createdAt'] as Timestamp : null,
      purchaseStatus: (map['purchaseStatus'] as String? ?? '').trim(),
      organizerProfile: OrganizerProfile.fromRootMap(map),
      analytics: MasterLeagueAnalytics.fromRootMap(map),
      followersCount: _asInt(map['followersCount']),
      createdViaAttemptId: (map['createdViaAttemptId'] as String? ?? '').trim(),
      sourcePaymentId: (map['sourcePaymentId'] as String? ?? '').trim(),
      sourceReceiptId: (map['sourceReceiptId'] as String? ?? '').trim(),
      initialCompetition: initialRaw is Map<String, dynamic>
          ? MasterLeagueCompetitionDraft.fromMap(initialRaw)
          : (initialRaw is Map
              ? MasterLeagueCompetitionDraft.fromMap(
                  Map<String, dynamic>.from(initialRaw),
                )
              : null),
      verificationStatus: (map['verificationStatus'] as String? ?? 'none').trim(),
      verifiedBadge: _asBool(map['verifiedBadge']),
      verificationRequestId:
          (map['verificationRequestId'] as String? ?? '').trim(),
      verificationReceiptId:
          (map['verificationReceiptId'] as String? ?? '').trim(),
      verificationPaymentId:
          (map['verificationPaymentId'] as String? ?? '').trim(),
      verificationProvider:
          (map['verificationProvider'] as String? ?? '').trim(),
      verificationRequestedAtMs: _asInt(map['verificationRequestedAtMs']),
      verificationApprovedAtMs: _asInt(map['verificationApprovedAtMs']),
      verificationExpiresAtMs: _asInt(map['verificationExpiresAtMs']),
      verificationReviewedBy:
          (map['verificationReviewedBy'] as String? ?? '').trim(),
      verificationNote: (map['verificationNote'] as String? ?? '').trim(),
      verificationRequestType:
          (map['verificationRequestType'] as String? ?? 'initial').trim(),
    );
  }

  factory MasterLeague.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    return MasterLeague.fromMap(doc.id, doc.data() ?? <String, dynamic>{});
  }

  bool isOwner(String uid) => ownerId.trim().isNotEmpty && ownerId.trim() == uid.trim();

  bool get isActive {
    final status = purchaseStatus.trim().toLowerCase();
    return status.isEmpty || status == 'active';
  }

  bool get isVerifiedOrganizer =>
      verifiedBadge || verificationStatus.trim().toLowerCase() == 'approved';

  bool get isVerificationPending =>
      verificationStatus.trim().toLowerCase() == 'pending';

  bool get isVerificationRejected =>
      verificationStatus.trim().toLowerCase() == 'rejected';

  bool get verificationExpired {
    final expiry = verificationExpiresAtMs;
    if (expiry <= 0) return false;
    return expiry <= DateTime.now().millisecondsSinceEpoch;
  }

  bool get canRenewVerification {
    return isVerifiedOrganizer || verificationExpired;
  }

  bool get lastVerificationWasRenewal =>
      verificationRequestType.trim().toLowerCase() == 'renewal';

  bool canSeeOrganizerProfile(String uid) {
    final cleanUid = uid.trim();
    if (cleanUid.isEmpty) return false;
    if (isOwner(cleanUid)) return true;
    if (memberIds.contains(cleanUid)) return true;

    final role = roles[cleanUid]?.trim().toLowerCase() ?? '';
    return role == 'admin' || role == 'moderator';
  }

  int get maxTeamsPerLeague {
    switch (plan) {
      case MasterLeaguePlan.basic:
        return 16;
      case MasterLeaguePlan.pro:
        return 24;
      case MasterLeaguePlan.elite:
        return 64;
    }
  }

  bool get isDiscoverable {
    return name.trim().isNotEmpty && isActive;
  }
}
