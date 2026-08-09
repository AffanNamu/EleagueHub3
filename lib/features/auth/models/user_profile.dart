// lib/features/auth/models/user_profile.dart

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../master_leagues/domain/master_league_plan.dart';
import '../../verification/domain/badge_model.dart';

class UserProfile {
  const UserProfile({
    required this.userId,
    required this.teamName,
    required this.authProvider,
    required this.createdAtMs,
    required this.updatedAtMs,
    required this.shareId,
    required this.quickMessagesCustom,
    required this.photoUrl,
    required this.profileImageUrl,
    required this.teamImageUrl,
    required this.isPremium,
    required this.premiumExpiresAtMs,
    required this.isVerified,
    required this.verifiedAtMs,
    required this.verificationExpiresAtMs,
    required this.verificationStatus,
    required this.activePlanId,
    required this.activePlanDurationId,
    required this.planPurchasedAtMs,
    required this.planExpiresAtMs,
    required this.planReceiptId,
    required this.planProvider,
    // Badge system — defaults to empty so all existing
    // call-sites that do not pass this compile unchanged.
    this.verificationBadges = VerificationBadges.empty,
    // Username system — NEW. Defaults to '' so all existing
    // call-sites that do not pass these compile unchanged.
    // `username` preserves the user's chosen casing for display;
    // `usernameLower` is the canonical, unique, lowercase value used
    // for comparisons, storage keys, and the `usernames/{id}`
    // reservation collection. These are ALWAYS written together by
    // UserProfileRepository — never write one without the other.
    this.username = '',
    this.usernameLower = '',
  });

  final String userId;
  final String teamName;
  final String authProvider;
  final int createdAtMs;
  final int updatedAtMs;
  final String shareId;
  final List<String> quickMessagesCustom;
  final String photoUrl;
  final String profileImageUrl;
  final String teamImageUrl;
  final bool isPremium;
  final int premiumExpiresAtMs;
  final bool isVerified;
  final int verifiedAtMs;
  final int verificationExpiresAtMs;
  final String verificationStatus;

  final String activePlanId;
  final String activePlanDurationId;
  final int planPurchasedAtMs;
  final int planExpiresAtMs;
  final String planReceiptId;
  final String planProvider;

  /// Badge ownership state.
  ///
  /// Populated from the nested "verification" map in the Firestore
  /// user document.  Defaults to [VerificationBadges.empty] so that
  /// all existing code that constructs [UserProfile] without this
  /// field continues to compile and behave correctly.
  final VerificationBadges verificationBadges;

  /// User-facing username, e.g. "corebridge" (no leading '@' — the
  /// '@' is a presentation-only prefix, see [UsernameUtils.toDisplay]).
  /// This is the SAME string as [usernameLower] in current usage
  /// (canonical storage is lowercase-only), kept as a separate field
  /// only so a future casing-preserving display name could diverge
  /// from the canonical comparison key without a migration.
  final String username;

  /// Canonical lowercase form of [username]. This is what uniqueness
  /// is enforced against (via the `usernames/{usernameLower}` document)
  /// and what should be used for any equality/lookup comparison.
  final String usernameLower;

  // ── Badge convenience getters ─────────────────────────────────────────────

  /// True when the green verified badge is active (not expired).
  bool get isGreenVerified => verificationBadges.isGreenActive;

  /// True when the gold organizer badge is active (not expired).
  bool get isOrganizerVerified =>
      verificationBadges.isOrganizerActive;

  /// True when the staff / ambassador badge is active (not expired).
  bool get isStaffVerified => verificationBadges.isStaffActive;

  // ── Username convenience getters ──────────────────────────────────────────

  bool get hasUsername => usernameLower.trim().isNotEmpty;

  /// "@username" for display, or '' if no username has been assigned
  /// yet (e.g. mid-migration for an existing user).
  String get usernameDisplay {
    final value = usernameLower.trim();
    if (value.isEmpty) return '';
    return '@$value';
  }

  // ── Existing getters — unchanged ──────────────────────────────────────────

  String get effectivePhotoUrl {
    if (profileImageUrl.trim().isNotEmpty) {
      return profileImageUrl.trim();
    }
    if (teamImageUrl.trim().isNotEmpty) return teamImageUrl.trim();
    return photoUrl.trim();
  }

  bool get hasShareId => shareId.trim().isNotEmpty;

  String get effectiveShareId {
    final stored = shareId.trim();
    if (stored.isNotEmpty) return stored;
    return deriveShareIdFromUid(userId);
  }

  bool get premiumActive {
    if (!isPremium) return false;
    if (premiumExpiresAtMs <= 0) return isPremium;
    return premiumExpiresAtMs >
        DateTime.now().millisecondsSinceEpoch;
  }

  bool get verifiedActive {
    if (!isVerified) return false;
    if (verificationExpiresAtMs <= 0) return true;
    return verificationExpiresAtMs >
        DateTime.now().millisecondsSinceEpoch;
  }

  bool get verificationPending =>
      verificationStatus.trim().toLowerCase() == 'pending';

  bool get hasStoredPlanId => activePlanId.trim().isNotEmpty;

  bool get hasPlanActive {
    final storedPlan =
        MasterLeaguePlan.tryFromString(activePlanId);
    if (storedPlan != null) {
      if (storedPlan.isFree) return true;
      return planExpiresAtMs >
          DateTime.now().millisecondsSinceEpoch;
    }

    // backward compatibility: old premium user gets league access
    if (premiumActive) return true;

    return false;
  }

  MasterLeaguePlan? get activePlan {
    final storedPlan =
        MasterLeaguePlan.tryFromString(activePlanId);
    if (storedPlan != null) {
      if (storedPlan.isFree) return storedPlan;
      if (planExpiresAtMs >
          DateTime.now().millisecondsSinceEpoch) {
        return storedPlan;
      }
    }

    // fallback: old premium users behave like pro until migrated
    if (premiumActive) return MasterLeaguePlan.pro;

    return null;
  }

  PlanDuration? get activePlanDuration {
    final plan = activePlan;
    if (plan == null) return null;

    final stored =
        PlanDuration.fromString(activePlanDurationId);
    if (activePlanDurationId.trim().isNotEmpty) return stored;

    if (plan.isFree) return PlanDuration.threeMonths;

    return PlanDuration.threeMonths;
  }

  UserPlanSubscription? get planSubscription {
    final plan = activePlan;
    final duration = activePlanDuration;
    if (plan == null || duration == null) return null;

    final purchasedAt =
        planPurchasedAtMs > 0 ? planPurchasedAtMs : createdAtMs;

    final expiresAt = plan.isFree
        ? 0
        : (planExpiresAtMs > 0
            ? planExpiresAtMs
            : premiumExpiresAtMs);

    return UserPlanSubscription(
      plan: plan,
      duration: duration,
      purchasedAtMs: purchasedAt,
      expiresAtMs: expiresAt,
      receiptId: planReceiptId.trim(),
      provider: planProvider.trim(),
    );
  }

  int get planDaysRemaining {
    final sub = planSubscription;
    if (sub == null) return 0;
    return sub.daysRemaining;
  }

  bool get planExpiringSoon {
    final sub = planSubscription;
    if (sub == null) return false;
    return sub.isExpiringSoon;
  }

  bool get canAccessLeagues => hasPlanActive;
  bool get canAccessMasterLeagues => hasPlanActive;

  String get displayName {
    final name = teamName.trim();
    if (name.isNotEmpty) return name;
    final shortId = effectiveShareId.trim();
    if (shortId.isNotEmpty) return shortId;
    return 'User';
  }

  // ── copyWith ──────────────────────────────────────────────────────────────

  UserProfile copyWith({
    String? userId,
    String? teamName,
    String? authProvider,
    int? createdAtMs,
    int? updatedAtMs,
    String? shareId,
    List<String>? quickMessagesCustom,
    String? photoUrl,
    String? profileImageUrl,
    String? teamImageUrl,
    bool? isPremium,
    int? premiumExpiresAtMs,
    bool? isVerified,
    int? verifiedAtMs,
    int? verificationExpiresAtMs,
    String? verificationStatus,
    String? activePlanId,
    String? activePlanDurationId,
    int? planPurchasedAtMs,
    int? planExpiresAtMs,
    String? planReceiptId,
    String? planProvider,
    VerificationBadges? verificationBadges,
    String? username,
    String? usernameLower,
  }) {
    return UserProfile(
      userId: userId ?? this.userId,
      teamName: teamName ?? this.teamName,
      authProvider: authProvider ?? this.authProvider,
      createdAtMs: createdAtMs ?? this.createdAtMs,
      updatedAtMs: updatedAtMs ?? this.updatedAtMs,
      shareId: shareId ?? this.shareId,
      quickMessagesCustom:
          quickMessagesCustom ?? this.quickMessagesCustom,
      photoUrl: photoUrl ?? this.photoUrl,
      profileImageUrl: profileImageUrl ?? this.profileImageUrl,
      teamImageUrl: teamImageUrl ?? this.teamImageUrl,
      isPremium: isPremium ?? this.isPremium,
      premiumExpiresAtMs:
          premiumExpiresAtMs ?? this.premiumExpiresAtMs,
      isVerified: isVerified ?? this.isVerified,
      verifiedAtMs: verifiedAtMs ?? this.verifiedAtMs,
      verificationExpiresAtMs:
          verificationExpiresAtMs ?? this.verificationExpiresAtMs,
      verificationStatus:
          verificationStatus ?? this.verificationStatus,
      activePlanId: activePlanId ?? this.activePlanId,
      activePlanDurationId:
          activePlanDurationId ?? this.activePlanDurationId,
      planPurchasedAtMs:
          planPurchasedAtMs ?? this.planPurchasedAtMs,
      planExpiresAtMs: planExpiresAtMs ?? this.planExpiresAtMs,
      planReceiptId: planReceiptId ?? this.planReceiptId,
      planProvider: planProvider ?? this.planProvider,
      verificationBadges:
          verificationBadges ?? this.verificationBadges,
      username: username ?? this.username,
      usernameLower: usernameLower ?? this.usernameLower,
    );
  }

  // ── toJson ────────────────────────────────────────────────────────────────

  /// NOTE: `username`/`usernameLower` are DELIBERATELY NOT included
  /// here. Username writes must always go through
  /// `UserProfileRepository.updateUsername()` /
  /// `ensureUsernameIfMissing()`, which run inside a Firestore
  /// transaction that also reserves the name in the top-level
  /// `usernames/{usernameLower}` collection. Writing username via a
  /// generic `saveOrUpdateSelf()` / `toJson()` merge would bypass that
  /// reservation and could silently desync the two collections.
  /// This mirrors how `verification` badge state is intentionally
  /// excluded from writes here (see comment below) despite being
  /// included read-only for completeness.
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'userId': userId,
      'teamName': teamName,
      'authProvider': authProvider,
      'createdAt': createdAtMs,
      'updatedAt': updatedAtMs,
      if (shareId.trim().isNotEmpty) 'shareId': shareId.trim(),
      if (quickMessagesCustom.isNotEmpty)
        'quickMessagesCustom': quickMessagesCustom,
      if (photoUrl.trim().isNotEmpty)
        'photoUrl': photoUrl.trim(),
      if (profileImageUrl.trim().isNotEmpty)
        'profileImageUrl': profileImageUrl.trim(),
      if (teamImageUrl.trim().isNotEmpty)
        'teamImageUrl': teamImageUrl.trim(),
      'isPremium': isPremium,
      'premiumExpiresAtMs': premiumExpiresAtMs,
      'isVerified': isVerified,
      'verifiedAtMs': verifiedAtMs,
      'verificationExpiresAtMs': verificationExpiresAtMs,
      'verificationStatus': verificationStatus,
      'activePlanId': activePlanId,
      'activePlanDurationId': activePlanDurationId,
      'planPurchasedAtMs': planPurchasedAtMs,
      'planExpiresAtMs': planExpiresAtMs,
      'planReceiptId': planReceiptId,
      'planProvider': planProvider,
      // Badge state is stored separately by BadgeRepository
      // and should NOT be written here to avoid overwriting it.
      // We include it read-only for completeness.
      'verification': verificationBadges.toMap(),
      // Username is stored separately via UserProfileRepository's
      // transactional username methods and should NOT be written
      // here to avoid bypassing the uniqueness reservation. Included
      // read-only for completeness.
      if (username.trim().isNotEmpty) 'username': username.trim(),
      if (usernameLower.trim().isNotEmpty)
        'usernameLower': usernameLower.trim(),
    };
  }

  // ── fromDoc / fromMap ─────────────────────────────────────────────────────

  factory UserProfile.fromDoc(
      DocumentSnapshot<Map<String, dynamic>> doc) {
    return UserProfile.fromMap(
      doc.id,
      doc.data() ?? <String, dynamic>{},
    );
  }

  factory UserProfile.fromMap(
    String fallbackUserId,
    Map<String, dynamic> map,
  ) {
    final userId =
        (map['userId'] as String? ?? fallbackUserId).trim();

    final bool verifiedFlag = map['isVerified'] == true ||
        map['verifiedBadge'] == true ||
        (map['verificationStatus'] as String? ?? '')
                .trim()
                .toLowerCase() ==
            'approved';

    // ── Parse badge state from the nested "verification" map ──────────────
    VerificationBadges badges = VerificationBadges.empty;
    final rawVerification = map['verification'];
    if (rawVerification is Map) {
      try {
        badges = VerificationBadges.fromMap(
          rawVerification.cast<String, dynamic>(),
        );
      } catch (_) {
        // Malformed data — fall back to empty badges.
        badges = VerificationBadges.empty;
      }
    }
    // ─────────────────────────────────────────────────────────────────────

    final rawUsername = (map['username'] as String? ?? '').trim();
    final rawUsernameLower =
        (map['usernameLower'] as String? ?? '').trim().toLowerCase();

    return UserProfile(
      userId: userId,
      teamName: (map['teamName'] as String? ?? '').trim(),
      authProvider:
          (map['authProvider'] as String? ?? '').trim(),
      createdAtMs: _readMs(map['createdAt']),
      updatedAtMs: _readMs(map['updatedAt']),
      shareId: (map['shareId'] as String? ?? '').trim(),
      quickMessagesCustom:
          _readStringList(map['quickMessagesCustom']),
      photoUrl: (map['photoUrl'] as String? ?? '').trim(),
      profileImageUrl:
          (map['profileImageUrl'] as String? ?? '').trim(),
      teamImageUrl:
          (map['teamImageUrl'] as String? ?? '').trim(),
      isPremium: map['isPremium'] == true,
      premiumExpiresAtMs: _readMs(map['premiumExpiresAtMs']),
      isVerified: verifiedFlag,
      verifiedAtMs: _readMs(map['verifiedAtMs']),
      verificationExpiresAtMs: _readMs(
        map['verificationExpiresAtMs'] ??
            map['verifiedExpiresAtMs'],
      ),
      verificationStatus:
          (map['verificationStatus'] as String? ?? '').trim(),
      activePlanId:
          (map['activePlanId'] as String? ?? '').trim(),
      activePlanDurationId:
          (map['activePlanDurationId'] as String? ?? '').trim(),
      planPurchasedAtMs: _readMs(map['planPurchasedAtMs']),
      planExpiresAtMs: _readMs(map['planExpiresAtMs']),
      planReceiptId:
          (map['planReceiptId'] as String? ?? '').trim(),
      planProvider:
          (map['planProvider'] as String? ?? '').trim(),
      verificationBadges: badges,
      username: rawUsername,
      // Guard against any legacy/manual doc that has `username` set
      // but `usernameLower` missing — fall back to deriving it from
      // `username` so hasUsername/usernameDisplay behave correctly
      // even before the next ensureUsernameIfMissing() pass.
      usernameLower: rawUsernameLower.isNotEmpty
          ? rawUsernameLower
          : rawUsername.toLowerCase(),
    );
  }

  // ── Private helpers ───────────────────────────────────────────────────────

  static int _readMs(dynamic raw) {
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    if (raw is Timestamp) {
      return raw.toDate().millisecondsSinceEpoch;
    }
    if (raw is DateTime) return raw.millisecondsSinceEpoch;
    return 0;
  }

  static List<String> _readStringList(dynamic raw) {
    if (raw is! List) return const <String>[];
    final out = <String>[];
    for (final item in raw) {
      final value = item is String ? item.trim() : '';
      if (value.isNotEmpty) out.add(value);
    }
    return List<String>.unmodifiable(out);
  }

  static String deriveShareIdFromUid(String uid) {
    final clean =
        uid.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').trim();
    if (clean.isEmpty) return '';

    final base = clean.length >= 8
        ? clean.substring(0, 8)
        : clean.padRight(8, 'X');

    return 'eS$base';
  }
}
