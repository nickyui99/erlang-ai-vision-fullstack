import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'app/sentineledge_app.dart';
import 'app/session_controller.dart';
export 'app/sentineledge_app.dart';
import 'firebase_options.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  if (kIsWeb) {
    usePathUrlStrategy();
  }
  final notificationMessengerKey = GlobalKey<ScaffoldMessengerState>();
  final session = SessionController(
    notificationMessengerKey: notificationMessengerKey,
  );
  runApp(
    ErlangVisionApp(
      session: session,
      scaffoldMessengerKey: notificationMessengerKey,
    ),
  );
  unawaited(_initializeStartup(session));
}

Future<void> _initializeStartup(SessionController session) async {
  if (DefaultFirebaseOptions.isConfigured) {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    if (!kIsWeb) {
      await GoogleSignIn.instance.initialize(
        serverClientId: DefaultFirebaseOptions.googleWebClientId.isEmpty
            ? null
            : DefaultFirebaseOptions.googleWebClientId,
      );
    }
  }
  await session.restore();
}
