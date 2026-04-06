import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      default:
        return web;
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyCGY5p4eQ4sAqkNaYBxP9pbmEBFOFWHEhM',
    authDomain: 'esportlyic.firebaseapp.com',
    projectId: 'esportlyic',
    storageBucket: 'esportlyic.firebasestorage.app',
    messagingSenderId: '155243307303',
    appId: '1:155243307303:web:966ec978b28709f1878902',
    measurementId: 'G-6RWEGP59BT',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyCGY5p4eQ4sAqkNaYBxP9pbmEBFOFWHEhM',
    authDomain: 'esportlyic.firebaseapp.com',
    projectId: 'esportlyic',
    storageBucket: 'esportlyic.firebasestorage.app',
    messagingSenderId: '155243307303',
    appId: '1:155243307303:web:966ec978b28709f1878902',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyCGY5p4eQ4sAqkNaYBxP9pbmEBFOFWHEhM',
    authDomain: 'esportlyic.firebaseapp.com',
    projectId: 'esportlyic',
    storageBucket: 'esportlyic.firebasestorage.app',
    messagingSenderId: '155243307303',
    appId: '1:155243307303:web:966ec978b28709f1878902',
  );
}
