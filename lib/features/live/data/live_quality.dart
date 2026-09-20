enum LiveQualityPreset { low, medium, high }

class LiveCaptureConfig {
  const LiveCaptureConfig({
    required this.screenWidth,
    required this.screenHeight,
    required this.screenFps,
    required this.cameraWidth,
    required this.cameraHeight,
    required this.cameraFps,
  });

  final int screenWidth;
  final int screenHeight;
  final int screenFps;

  final int cameraWidth;
  final int cameraHeight;
  final int cameraFps;

  static LiveCaptureConfig fromPreset(LiveQualityPreset preset) {
    switch (preset) {
      case LiveQualityPreset.low:
        return const LiveCaptureConfig(
          screenWidth: 960,
          screenHeight: 540,
          screenFps: 15,
          cameraWidth: 640,
          cameraHeight: 360,
          cameraFps: 15,
        );
      case LiveQualityPreset.medium:
        return const LiveCaptureConfig(
          screenWidth: 1280,
          screenHeight: 720,
          screenFps: 30,
          cameraWidth: 640,
          cameraHeight: 480,
          cameraFps: 30,
        );
      case LiveQualityPreset.high:
        return const LiveCaptureConfig(
          screenWidth: 1920,
          screenHeight: 1080,
          screenFps: 30,
          cameraWidth: 1280,
          cameraHeight: 720,
          cameraFps: 30,
        );
    }
  }

  @override
  String toString() =>
      'screen=${screenWidth}x$screenHeight@$screenFps cam=${cameraWidth}x$cameraHeight@$cameraFps';
}

// NOTE (i18n): qualityLabel is only referenced from local_live_service.dart,
// the legacy LAN live path with no active presentation-layer caller (see
// that file's note), so this label is not actually shown to end users
// today. It's a top-level function with no BuildContext; left as English.
String qualityLabel(LiveQualityPreset p) {
  switch (p) {
    case LiveQualityPreset.low:
      return 'Low';
    case LiveQualityPreset.medium:
      return 'Medium';
    case LiveQualityPreset.high:
      return 'High';
  }
}
