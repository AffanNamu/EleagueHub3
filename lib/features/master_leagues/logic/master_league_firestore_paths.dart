/// Centralized Firestore path/collection constants for the Master League feature.
///
/// Keeping these as constants reduces typos across:
/// - repositories
/// - entitlement service
/// - (future) Cloud Functions / admin tools
class MasterLeagueFirestorePaths {
  static const String masterLeaguesCollection = 'master_leagues';

  static const String usersCollection = 'users';
  static const String entitlementsSubcollection = 'entitlements';

  /// Entitlement document id under `users/{uid}/entitlements/{id}`.
  static const String masterLeagueEntitlementId = 'master_league';
}
