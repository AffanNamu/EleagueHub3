// Conditional import:
//   On web     → uses ua_detector_web.dart  (real dart:js_util)
//   On Android/iOS → uses ua_detector_stub.dart (always false)
export 'ua_detector_stub.dart'
    if (dart.library.html) 'ua_detector_web.dart';
