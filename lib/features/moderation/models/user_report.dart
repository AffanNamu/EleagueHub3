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
