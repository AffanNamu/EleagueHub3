// Stub for non-web platforms (Android, iOS).
// This file is used when dart:js is not available.

/// Always returns false on mobile — every device is treated
/// as a desktop/native app on Android and iOS.
bool isRealMobileBrowser(double width) => false;
