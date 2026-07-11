import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../firebase_options.dart';
import '../shared/event_alert.dart';
import 'backend_auth_client.dart';

class PushNotificationService {
  PushNotificationService({FirebaseMessaging? messaging})
    : _messaging = messaging;

  final FirebaseMessaging? _messaging;
  StreamSubscription<String>? _tokenRefreshSubscription;
  StreamSubscription<RemoteMessage>? _foregroundSubscription;
  String? _registeredToken;

  FirebaseMessaging get _instance => _messaging ?? FirebaseMessaging.instance;

  Future<void> registerForCurrentUser(
    ErlangVisionApiClient apiClient, {
    ScaffoldMessengerState? messenger,
  }) async {
    if (!DefaultFirebaseOptions.isConfigured) return;

    final settings = await _instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );
    if (settings.authorizationStatus == AuthorizationStatus.denied) return;

    await _registerCurrentToken(apiClient);
    await _tokenRefreshSubscription?.cancel();
    _tokenRefreshSubscription = _instance.onTokenRefresh.listen((token) async {
      await _registerToken(apiClient, token);
    });

    if (messenger != null) {
      await _foregroundSubscription?.cancel();
      _foregroundSubscription = FirebaseMessaging.onMessage.listen((message) {
        _showForegroundMessage(messenger, message);
      });
    }
  }

  Future<void> deregisterForCurrentUser(ErlangVisionApiClient apiClient) async {
    await _tokenRefreshSubscription?.cancel();
    await _foregroundSubscription?.cancel();
    _tokenRefreshSubscription = null;
    _foregroundSubscription = null;

    final token = _registeredToken;
    _registeredToken = null;
    if (token == null || token.isEmpty) return;

    try {
      await apiClient.deregisterPushToken(token);
    } catch (_) {
      // Logout should continue even if the backend token cleanup is best-effort.
    }
  }

  Future<void> dispose() async {
    await _tokenRefreshSubscription?.cancel();
    await _foregroundSubscription?.cancel();
  }

  Future<void> _registerCurrentToken(ErlangVisionApiClient apiClient) async {
    try {
      final token = await _instance.getToken(
        vapidKey: kIsWeb ? _webVapidKey : null,
      );
      if (token == null || token.isEmpty) return;
      await _registerToken(apiClient, token);
    } catch (_) {
      // Web push requires a valid VAPID key and service worker; native builds may
      // also decline permission. In both cases the app remains usable.
    }
  }

  Future<void> _registerToken(
    ErlangVisionApiClient apiClient,
    String token,
  ) async {
    await apiClient.registerPushToken(token: token, platform: _platformName());
    _registeredToken = token;
  }

  void _showForegroundMessage(
    ScaffoldMessengerState messenger,
    RemoteMessage message,
  ) {
    final title = message.notification?.title ?? 'Security alert';
    final body = message.notification?.body ??
        message.data['summary']?.toString() ??
        message.data['event_type']?.toString() ??
        'A camera event needs review.';
    // Shared banner + sound/haptic (covers mobile, where realtime SSE is absent).
    showEventAlert(
      messenger,
      title: title,
      body: body,
      tone: toneForSeverity(message.data['severity']?.toString()),
    );
  }

  String _platformName() {
    if (kIsWeb) return 'web';
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => 'android',
      TargetPlatform.iOS => 'ios',
      TargetPlatform.macOS => 'macos',
      TargetPlatform.windows => 'windows',
      TargetPlatform.linux => 'linux',
      TargetPlatform.fuchsia => 'fuchsia',
    };
  }
}

const _webVapidKey = String.fromEnvironment('FIREBASE_MESSAGING_VAPID_KEY');