// lib/features/verification/domain/badge_model.dart
import 'package:cloud_firestore/cloud_firestore.dart';

/// Describes WHY a badge was granted.
/// This allows future management, expiration logic, and audit trails.
enum BadgeSource {
  manualPurchase,
  proSubscription,
  eliteSubscription,
  adminGranted,
}

extension BadgeSourceExtension on BadgeSource {
  String get firestoreValue {
    switch (this) {
      case BadgeSource.manualPurchase:
        return 'manual_purchase';
      case BadgeSource.proSubscription:
        return 'pro_subscription';
      case BadgeSource.eliteSubscription:
        return 'elite_subscription';
      case BadgeSource.adminGranted:
        return 'admin_granted';
    }
  }

  static BadgeSource fromString(String? value) {
    switch (value) {
      case 'manual_purchase':
        return BadgeSource.manualPurchase;
      case 'pro_subscription':
        return BadgeSource.proSubscription;
      case 'elite_subscription':
        return BadgeSource.eliteSubscription;
      case 'admin_granted':
        return BadgeSource.adminGranted;
      default:
        return BadgeSource.manualPurchase;
    }
  }
}

/// Immutable value object representing a user's verification state.
///
/// Firestore path: users/{uid}/verification (as a sub-document map
/// merged into the user document under the key "verification").
///
/// Fields stored flat on the user document:
/// verification.greenVerified bool
/// verification.organizerVerified bool
/// verification.staffVerified bool
/// verification.greenSource String?
/// verification.organizerSource String?
/// verification.staffSource String?
/// verification.greenExpiresAt Timestamp?
/// verification.organizerExpiresAt Timestamp?
/// verification.staffExpiresAt Timestamp?
class VerificationBadges {
  final bool greenVerified;
  final bool organizerVerified;
  final bool staffVerified;
  final BadgeSource? greenSource;
  final BadgeSource? organizerSource;
  final BadgeSource? staffSource;
  
  /// null means the badge never expires (manual_purchase / admin_granted).
  final DateTime? greenExpiresAt;
  final DateTime? organizerExpiresAt;
  final DateTime? staffExpiresAt;

  const VerificationBadges({
    this.greenVerified = false,
    this.organizerVerified = false,
    this.staffVerified = false,
    this.greenSource,
    this.organizerSource,
    this.staffSource,
    this.greenExpiresAt,
    this.organizerExpiresAt,
    this.staffExpiresAt,
  });

  static const empty = VerificationBadges();

  /// Whether the green badge is currently active (not expired).
  bool get isGreenActive {
    if (!greenVerified) return false;
    if (greenExpiresAt == null) return true;
    return DateTime.now().isBefore(greenExpiresAt!);
  }

  /// Whether the organizer badge is currently active (not expired).
  bool get isOrganizerActive {
    if (!organizerVerified) return false;
    if (organizerExpiresAt == null) return true;
    return DateTime.now().isBefore(organizerExpiresAt!);
  }

  /// Whether the staff badge is currently active (not expired).
  bool get isStaffActive {
    if (!staffVerified) return false;
    if (staffExpiresAt == null) return true;
    return DateTime.now().isBefore(staffExpiresAt!);
  }

  factory VerificationBadges.fromMap(Map<String, dynamic> map) {
    DateTime? _parseTimestamp(dynamic raw) {
      if (raw == null) return null;
      if (raw is Timestamp) return raw.toDate();
      if (raw is int) {
        return DateTime.fromMillisecondsSinceEpoch(raw);
      }
      return null;
    }

    return VerificationBadges(
      greenVerified: (map['greenVerified'] as bool?) ?? false,
      organizerVerified: (map['organizerVerified'] as bool?) ?? false,
      staffVerified: (map['staffVerified'] as bool?) ?? false,
      greenSource: BadgeSourceExtension.fromString(map['greenSource'] as String?),
      organizerSource: BadgeSourceExtension.fromString(map['organizerSource'] as String?),
      staffSource: BadgeSourceExtension.fromString(map['staffSource'] as String?),
      greenExpiresAt: _parseTimestamp(map['greenExpiresAt']),
      organizerExpiresAt: _parseTimestamp(map['organizerExpiresAt']),
      staffExpiresAt: _parseTimestamp(map['staffExpiresAt']),
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'greenVerified': greenVerified,
      'organizerVerified': organizerVerified,
      'staffVerified': staffVerified,
      if (greenSource != null) 'greenSource': greenSource!.firestoreValue,
      if (organizerSource != null) 'organizerSource': organizerSource!.firestoreValue,
      if (staffSource != null) 'staffSource': staffSource!.firestoreValue,
      'greenExpiresAt': greenExpiresAt != null ? Timestamp.fromDate(greenExpiresAt!) : null,
      'organizerExpiresAt': organizerExpiresAt != null ? Timestamp.fromDate(organizerExpiresAt!) : null,
      'staffExpiresAt': staffExpiresAt != null ? Timestamp.fromDate(staffExpiresAt!) : null,
    };
  }

  VerificationBadges copyWith({
    bool? greenVerified,
    bool? organizerVerified,
    bool? staffVerified,
    BadgeSource? greenSource,
    BadgeSource? organizerSource,
    BadgeSource? staffSource,
    DateTime? greenExpiresAt,
    DateTime? organizerExpiresAt,
    DateTime? staffExpiresAt,
    bool clearGreenExpiry = false,
    bool clearOrganizerExpiry = false,
    bool clearStaffExpiry = false,
  }) {
    return VerificationBadges(
      greenVerified: greenVerified ?? this.greenVerified,
      organizerVerified: organizerVerified ?? this.organizerVerified,
      staffVerified: staffVerified ?? this.staffVerified,
      greenSource: greenSource ?? this.greenSource,
      organizerSource: organizerSource ?? this.organizerSource,
      staffSource: staffSource ?? this.staffSource,
      greenExpiresAt: clearGreenExpiry ? null : (greenExpiresAt ?? this.greenExpiresAt),
      organizerExpiresAt: clearOrganizerExpiry ? null : (organizerExpiresAt ?? this.organizerExpiresAt),
      staffExpiresAt: clearStaffExpiry ? null : (staffExpiresAt ?? this.staffExpiresAt),
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is VerificationBadges &&
        other.greenVerified == greenVerified &&
        other.organizerVerified == organizerVerified &&
        other.staffVerified == staffVerified &&
        other.greenSource == greenSource &&
        other.organizerSource == organizerSource &&
        other.staffSource == staffSource &&
        other.greenExpiresAt == greenExpiresAt &&
        other.organizerExpiresAt == organizerExpiresAt &&
        other.staffExpiresAt == staffExpiresAt;
  }

  @override
  int get hashCode => Object.hash(
        greenVerified,
        organizerVerified,
        staffVerified,
        greenSource,
        organizerSource,
        staffSource,
        greenExpiresAt,
        organizerExpiresAt,
        staffExpiresAt,
      );
}
