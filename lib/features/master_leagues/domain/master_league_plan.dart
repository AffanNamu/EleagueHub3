/// Duration tier for subscription plans.
enum PlanDuration {
  threeMonths(
    id: '3mo',
    displayName: '3 Months',
    months: 3,
    discountLabel: '',
    multiplier: 1.0,
  ),
  sixMonths(
    id: '6mo',
    displayName: '6 Months',
    months: 6,
    discountLabel: 'Save 10%',
    multiplier: 1.8,
  ),
  yearly(
    id: 'yearly',
    displayName: '1 Year',
    months: 12,
    discountLabel: 'Save 25%',
    multiplier: 3.0,
  );

  const PlanDuration({
    required this.id,
    required this.displayName,
    required this.months,
    required this.discountLabel,
    required this.multiplier,
  });

  final String id;
  final String displayName;
  final int months;
  final String discountLabel;
  final double multiplier;

  bool get hasDiscount => discountLabel.isNotEmpty;

  /// Approximate duration in days (30 days per month).
  /// Used in several places for UI and non-authoritative expiry estimation.
  int get durationDays => months * 30;

  /// BACKWARD-COMPATIBILITY ALIAS:
  /// Some parts of the app (and prior agent changes) reference `duration.days`.
  /// This getter keeps the code compiling and provides a reasonable value.
  ///
  /// We compute the number of days until the "month-based expiry date"
  /// to better align with [expiryMsFromNow] instead of using a fixed 30-day
  /// multiplier only.
  int get days {
    final now = DateTime.now();
    final expiry = DateTime(now.year, now.month + months, now.day);

    final hours = expiry.difference(now).inHours;
    final computed = (hours / 24).ceil();

    // Safety: if DateTime math yields something weird, fall back to durationDays.
    return computed > 0 ? computed : durationDays;
  }

  int expiryMsFromNow() {
    final now = DateTime.now();
    final expiry = DateTime(now.year, now.month + months, now.day);
    return expiry.millisecondsSinceEpoch;
  }

  static PlanDuration fromString(String? raw) {
    final normalized = (raw ?? '').trim().toLowerCase();
    for (final value in values) {
      if (value.id == normalized) return value;
    }
    return threeMonths;
  }
}

/// Tiered plan for Organizer Pro Mode.
///
/// Basic  - free, 1 master league, 3 competitions
/// Pro    - paid, 5 master leagues, 9 competitions each
/// Elite  - paid, unlimited master leagues and unlimited competitions
enum MasterLeaguePlan {
  basic(
    id: 'basic',
    displayName: 'Basic',
    description: '1 master league, up to 3 competitions',
    maxMasterLeagues: 1,
    maxLeagues: 3,
    maxTeamsPerLeague: 999,
    isPopular: false,
    unlimitedMasterLeagues: false,
    unlimitedCompetitions: false,
    isFree: true,
  ),
  pro(
    id: 'pro',
    displayName: 'Pro',
    description: '5 master leagues, up to 9 competitions each',
    maxMasterLeagues: 5,
    maxLeagues: 9,
    maxTeamsPerLeague: 999,
    isPopular: true,
    unlimitedMasterLeagues: false,
    unlimitedCompetitions: false,
    isFree: false,
  ),
  elite(
    id: 'elite',
    displayName: 'Elite',
    description: 'Unlimited master leagues and competitions',
    maxMasterLeagues: 999,
    maxLeagues: 999,
    maxTeamsPerLeague: 999,
    isPopular: false,
    unlimitedMasterLeagues: true,
    unlimitedCompetitions: true,
    isFree: false,
  );

  const MasterLeaguePlan({
    required this.id,
    required this.displayName,
    required this.description,
    required this.maxMasterLeagues,
    required this.maxLeagues,
    required this.maxTeamsPerLeague,
    required this.isPopular,
    required this.unlimitedMasterLeagues,
    required this.unlimitedCompetitions,
    required this.isFree,
  });

  final String id;
  final String displayName;
  final String description;
  final int maxMasterLeagues;
  final int maxLeagues;
  final int maxTeamsPerLeague;
  final bool isPopular;
  final bool unlimitedMasterLeagues;
  final bool unlimitedCompetitions;
  final bool isFree;

  bool get isBasic => this == basic;
  bool get isPro => this == pro;
  bool get isElite => this == elite;

  /// Whether this plan requires payment (duration-based).
  bool get requiresPayment => !isFree;

  /// Check if user can create another working space given current count.
  bool canCreateWorkspace(int currentCount) {
    if (unlimitedMasterLeagues) return true;
    return currentCount < maxMasterLeagues;
  }

  /// Check if user can create another competition in a workspace given current count.
  bool canCreateCompetition(int currentCount) {
    if (unlimitedCompetitions) return true;
    return currentCount < maxLeagues;
  }

  /// Whether the payment button should show when creating a new workspace.
  /// For Basic (free): never show payment.
  /// For Pro: show payment only if at limit (needs upgrade to Elite).
  /// For Elite: never show payment (unlimited).
  bool shouldShowPaymentForWorkspace(int currentCount) {
    if (isFree) return false;
    if (unlimitedMasterLeagues) return false;
    return currentCount >= maxMasterLeagues;
  }

  static MasterLeaguePlan fromString(String? raw) {
    final normalized = (raw ?? '').trim().toLowerCase();
    for (final value in values) {
      if (value.id == normalized) return value;
    }
    return basic;
  }

  /// Returns null if the raw string doesn't match any plan (no fallback).
  static MasterLeaguePlan? tryFromString(String? raw) {
    final normalized = (raw ?? '').trim().toLowerCase();
    for (final value in values) {
      if (value.id == normalized) return value;
    }
    return null;
  }
}

/// Represents a user's active subscription.
class UserPlanSubscription {
  final MasterLeaguePlan plan;
  final PlanDuration duration;
  final int purchasedAtMs;
  final int expiresAtMs;
  final String receiptId;
  final String provider;

  const UserPlanSubscription({
    required this.plan,
    required this.duration,
    required this.purchasedAtMs,
    required this.expiresAtMs,
    required this.receiptId,
    required this.provider,
  });

  bool get isActive {
    // Basic (free) plans never expire
    if (plan.isFree) return true;
    return expiresAtMs > DateTime.now().millisecondsSinceEpoch;
  }

  bool get isExpired => !isActive;

  int get daysRemaining {
    if (plan.isFree) return 999;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (expiresAtMs <= now) return 0;
    return ((expiresAtMs - now) / (1000 * 60 * 60 * 24)).ceil();
  }

  bool get isExpiringSoon => !plan.isFree && isActive && daysRemaining <= 7;

  Map<String, dynamic> toMap() => <String, dynamic>{
        'plan': plan.id,
        'duration': duration.id,
        'purchasedAtMs': purchasedAtMs,
        'expiresAtMs': expiresAtMs,
        'receiptId': receiptId,
        'provider': provider,
      };

  factory UserPlanSubscription.fromMap(Map<String, dynamic> map) {
    return UserPlanSubscription(
      plan: MasterLeaguePlan.fromString(map['plan'] as String?),
      duration: PlanDuration.fromString(map['duration'] as String?),
      purchasedAtMs: (map['purchasedAtMs'] as num?)?.toInt() ?? 0,
      expiresAtMs: (map['expiresAtMs'] as num?)?.toInt() ?? 0,
      receiptId: (map['receiptId'] as String?) ?? '',
      provider: (map['provider'] as String?) ?? '',
    );
  }
}