import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

class DefaultFirebaseOptions {
  static const String _webApiKey = String.fromEnvironment(
    'FIREBASE_WEB_API_KEY',
  );
  static const String _webAppId = String.fromEnvironment('FIREBASE_WEB_APP_ID');
  static const String _webMessagingSenderId = String.fromEnvironment(
    'FIREBASE_WEB_MESSAGING_SENDER_ID',
  );
  static const String _androidApiKey = String.fromEnvironment(
    'FIREBASE_ANDROID_API_KEY',
  );
  static const String _androidAppId = String.fromEnvironment(
    'FIREBASE_ANDROID_APP_ID',
  );
  static const String _androidMessagingSenderId = String.fromEnvironment(
    'FIREBASE_ANDROID_MESSAGING_SENDER_ID',
  );
  static const String _iosApiKey = String.fromEnvironment(
    'FIREBASE_IOS_API_KEY',
  );
  static const String _iosAppId = String.fromEnvironment('FIREBASE_IOS_APP_ID');
  static const String _iosMessagingSenderId = String.fromEnvironment(
    'FIREBASE_IOS_MESSAGING_SENDER_ID',
  );
  static const String googleWebClientId = String.fromEnvironment(
    'FIREBASE_GOOGLE_WEB_CLIENT_ID',
  );
  static const String _firebaseProjectId = String.fromEnvironment(
    'FIREBASE_PROJECT_ID',
    defaultValue: 'sentineledge-e069b',
  );
  static const String _firebaseAuthDomain = String.fromEnvironment(
    'FIREBASE_AUTH_DOMAIN',
    defaultValue: 'sentineledge-e069b.firebaseapp.com',
  );
  static const String _iosBundleId = String.fromEnvironment(
    'FIREBASE_IOS_BUNDLE_ID',
    defaultValue: 'com.example.sentineledgeApp',
  );

  static bool get isConfigured {
    if (kIsWeb) return _webConfigured;

    return switch (defaultTargetPlatform) {
      TargetPlatform.android => _androidApiKey.isNotEmpty &&
          _androidAppId.isNotEmpty &&
          _androidMessagingSenderId.isNotEmpty &&
          googleWebClientId.isNotEmpty,
      TargetPlatform.iOS || TargetPlatform.macOS => _iosApiKey.isNotEmpty &&
          _iosAppId.isNotEmpty &&
          _iosMessagingSenderId.isNotEmpty,
      TargetPlatform.windows || TargetPlatform.linux || TargetPlatform.fuchsia =>
        _webConfigured,
    };
  }

  static bool get _webConfigured =>
      _webApiKey.isNotEmpty &&
      _webAppId.isNotEmpty &&
      _webMessagingSenderId.isNotEmpty;

  static FirebaseOptions get currentPlatform {
    if (kIsWeb) return web;

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
        return ios;
      case TargetPlatform.windows:
      case TargetPlatform.linux:
      case TargetPlatform.fuchsia:
        return web;
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: _webApiKey,
    appId: _webAppId,
    messagingSenderId: _webMessagingSenderId,
    projectId: _firebaseProjectId,
    authDomain: _firebaseAuthDomain,
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: _androidApiKey,
    appId: _androidAppId,
    messagingSenderId: _androidMessagingSenderId,
    projectId: _firebaseProjectId,
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: _iosApiKey,
    appId: _iosAppId,
    messagingSenderId: _iosMessagingSenderId,
    projectId: _firebaseProjectId,
    iosBundleId: _iosBundleId,
  );
}

