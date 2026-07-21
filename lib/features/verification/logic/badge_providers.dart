//feautures/verification/logic/badge_provider.dart
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/data/user_profile_repository.dart';
import '../../auth/models/user_profile.dart';
import '../data/badge_repository.dart';
import '../domain/badge_model.dart';
import '../logic/badge_service.dart';

/// Provides the [BadgeRepository] singleton.
final badgeRepositoryProvider = Provider<BadgeRepository>(
  (_) => BadgeRepository.instance,
);

/// Provides the [BadgeService] singleton.
final badgeServiceProvider = Provider<BadgeService>(
  (_) => BadgeService.instance,
);

/// Streams the [VerificationBadges] for any [userId].
///
/// Usage:
///   ref.watch(badgeStreamProvider('uid123'))
final badgeStreamProvider =
    StreamProvider.family<VerificationBadges, String>(
  (ref, userId) {
    if (userId.trim().isEmpty) {
      return const Stream.empty();
    }
    return ref.read(badgeRepositoryProvider).streamBadges(userId);
  },
);

/// Future-based single fetch for [VerificationBadges].
///
/// Usage:
///   ref.watch(badgeFetchProvider('uid123'))
final badgeFetchProvider =
    FutureProvider.family<VerificationBadges, String>(
  (ref, userId) async {
    if (userId.trim().isEmpty) {
      return VerificationBadges.empty;
    }
    return ref.read(badgeRepositoryProvider).fetchBadges(userId);
  },
);

/// Streams the current authenticated user's [UserProfile].
///
/// Used by MasterLeagueDetailsScreen to decide whether to show the
/// World Cup PREMIUM label (Basic users only).
final currentUserProfileProvider = StreamProvider<UserProfile?>((ref) {
  final uid = FirebaseAuth.instance.currentUser?.uid.trim() ?? '';
  if (uid.isEmpty) return Stream.value(null);

  return UserProfileRepository().watchByUserId(uid).handleError((_) {
    // Safe default: treat as Basic if anything goes wrong.
    return null;
  });
});