import 'dart:ui';

extension ColorCompat on Color {
  /// Compatibility for code that uses Color.withValues(alpha: ...)
  /// If your Flutter/Dart SDK version is below 3.27, this extension
  /// redirects withValues to the older withOpacity method.
  Color withValues({double? alpha}) {
    if (alpha == null) return this;
    return withOpacity(alpha);
  }
}
