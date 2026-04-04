class SupabaseConfig {
  static const String url = 'https://rswbkehnqhznwhbbcvvp.supabase.co';

  static const String anonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJzd2JrZWhucWh6bndoYmJjdnZwIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzE4MzIwNzAsImV4cCI6MjA4NzQwODA3MH0.iX2dK6BXNtEKC4SYKO3x2ZMmPB_8vpQffNLB3IvuDgc';

  static bool get isConfigured =>
      url.trim().isNotEmpty && anonKey.trim().isNotEmpty;

  static void assertConfigured() {
    if (!isConfigured) {
      throw StateError('Supabase is not configured.');
    }
  }
}
