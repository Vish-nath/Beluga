import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:beluga_health/firebase_options.dart';

void main() {
  test('Firebase apps use the configured Beluga project', () {
    expect(DefaultFirebaseOptions.android.projectId, 'beluga-c1b2b');
    expect(DefaultFirebaseOptions.ios.projectId, 'beluga-c1b2b');
    expect(DefaultFirebaseOptions.web.projectId, 'beluga-c1b2b');
    expect(
      DefaultFirebaseOptions.android.appId,
      '1:733897267439:android:8672797ff661af6250631a',
    );
    expect(
      DefaultFirebaseOptions.ios.iosBundleId,
      'com.example.belugaHealth',
    );
  });

  test('platform configuration selects an existing Firebase app', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    expect(
      DefaultFirebaseOptions.currentPlatform.appId,
      DefaultFirebaseOptions.android.appId,
    );
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    expect(
      DefaultFirebaseOptions.currentPlatform.appId,
      DefaultFirebaseOptions.ios.appId,
    );
    debugDefaultTargetPlatformOverride = null;
  });
}
