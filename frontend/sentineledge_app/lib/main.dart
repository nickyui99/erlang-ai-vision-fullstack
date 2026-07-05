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

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (kIsWeb) {
    usePathUrlStrategy();
  }
  if (DefaultFirebaseOptions.isConfigured) {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    if (!kIsWeb) {
      await GoogleSignIn.instance.initialize();
    }
  }

  final session = SessionController();
  // Fire-and-forget: the router shows a splash while status == restoring and
  // reacts (via refreshListenable) once the session resolves.
  unawaited(session.restore());

  runApp(SentinelEdgeApp(session: session));
}
