import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

class DefaultFirebaseOptions {
  static const String _webApiKey = String.fromEnvironment('FIREBASE_WEB_API_KEY');
  static const String _webAppId = String.fromEnvironment('FIREBASE_WEB_APP_ID');
  static const String _webMessagingSenderId = String.fromEnvironment('FIREBASE_WEB_MESSAGING_SENDER_ID');
  static const String _firebaseProjectId = String.fromEnvironment(
    'FIREBASE_PROJECT_ID',
    defaultValue: 'sentineledge-e069b',
  );
  static const String _firebaseAuthDomain = String.fromEnvironment(
    'FIREBASE_AUTH_DOMAIN',
    defaultValue: 'sentineledge-e069b.firebaseapp.com',
  );

  static bool get isConfigured =>
      _webApiKey.isNotEmpty && _webAppId.isNotEmpty && _webMessagingSenderId.isNotEmpty;

  static FirebaseOptions get currentPlatform {
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
    apiKey: 'replace-me',
    appId: 'replace-me',
    messagingSenderId: 'replace-me',
    projectId: 'sentineledge-e069b',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'replace-me',
    appId: 'replace-me',
    messagingSenderId: 'replace-me',
    projectId: 'sentineledge-e069b',
    iosBundleId: 'com.example.sentineledgeApp',
  );
}
