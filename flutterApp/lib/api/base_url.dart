import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;

/// Returns the correct base URL for your current runtime.
String pickBaseUrl() {
  if (kIsWeb) return 'http://localhost:5000';

  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
    // Android emulator special loopback to host machine
      return 'http://10.0.2.2:5000';
    case TargetPlatform.iOS:
      return 'http://localhost:5000';
    case TargetPlatform.macOS:
    case TargetPlatform.windows:
    case TargetPlatform.linux:
      return 'http://localhost:5000';
    default:
      return 'http://localhost:5000';
  }
}

//
// /// Returns the production base URL for all runtimes.
// String pickBaseUrl() {
//   const base = 'https://carbon-pawprint.onrender.com';
//   return base; // same for web, Android emulator, iOS, desktop
// }