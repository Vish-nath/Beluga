import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) return web;

    return switch (defaultTargetPlatform) {
      TargetPlatform.android => android,
      TargetPlatform.iOS || TargetPlatform.macOS => ios,
      _ => throw UnsupportedError(
          'Beluga Firebase is not configured for this platform.',
        ),
    };
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyDAp6Kh9u5O7O7dxgNWLvqeUlOzcv2cSgs',
    appId: '1:733897267439:android:8672797ff661af6250631a',
    messagingSenderId: '733897267439',
    projectId: 'beluga-c1b2b',
    storageBucket: 'beluga-c1b2b.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyBQWJEy2TFXnlveHBtGLp2O3wCk2z1WpBE',
    appId: '1:733897267439:ios:fbe277478f67553950631a',
    messagingSenderId: '733897267439',
    projectId: 'beluga-c1b2b',
    storageBucket: 'beluga-c1b2b.firebasestorage.app',
    iosBundleId: 'com.example.belugaHealth',
  );

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyAP6tZ835dJGWSNcv_4RkugjFWN5kWTz0Q',
    appId: '1:733897267439:web:aa3d899b796f563f50631a',
    messagingSenderId: '733897267439',
    projectId: 'beluga-c1b2b',
    authDomain: 'beluga-c1b2b.firebaseapp.com',
    storageBucket: 'beluga-c1b2b.firebasestorage.app',
  );
}
