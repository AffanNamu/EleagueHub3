/// What kind of content a report is about. Every report still carries a
/// `targetUserId` (the author of the content, or the profile itself for
/// [profile]) so the existing admin review queue can always resolve a
/// profile to show -- [contextId]/[contextLocation] on the report document
/// additionally locate the specific message/post/comment for review.
class ReportTargetType {
  static const profile = 'profile';
  static const message = 'message';
  static const post = 'post';
  static const comment = 'comment';

  static const List<String> all = [profile, message, post, comment];
}

class UserReportReason {
  static const spam = 'spam';
  static const harassment = 'harassment';
  static const impersonation = 'impersonation';
  static const cheating = 'cheating';
  static const other = 'other';

  static const List<String> all = [spam, harassment, impersonation, cheating, other];

  static String label(String reason) {
    switch (reason) {
      case spam:
        return 'Spam';
      case harassment:
        return 'Harassment';
      case impersonation:
        return 'Impersonation';
      case cheating:
        return 'Cheating';
      case other:
      default:
        return 'Other';
    }
  }
}
