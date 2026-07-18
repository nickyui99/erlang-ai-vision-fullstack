import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../firebase_options.dart';
import '../shared/event_alert.dart';
import 'browser_notification.dart' as browser_notification;
import 'backend_auth_client.dart';

/// High-importance channel for security alerts. Android shows notifications on
/// this channel as heads-up pop-ups with sound; it is also named in the Android
/// manifest as the FCM default channel so background/killed-app pushes land here
/// too. Keep the id in sync with
/// ``com.google.firebase.messaging.default_notification_channel_id``.
const _alertChannel = AndroidNotificationChannel(
  'security_alerts',
  'Security alerts',
  description: 'Camera detections that need your attention.',
  importance: Importance.high,
);

class PushNotificationService {
  PushNotificationService({
    FirebaseMessaging? messaging,
    FlutterLocalNotificationsPlugin? localNotifications,
  }) : _messaging = messaging,
       _localNotifications =
           localNotifications ?? FlutterLocalNotificationsPlugin();

  final FirebaseMessaging? _messaging;
  final FlutterLocalNotificationsPlugin _localNotifications;
  StreamSubscription<String>? _tokenRefreshSubscription;
  StreamSubscription<RemoteMessage>? _foregroundSubscription;
  String? _registeredToken;
  bool _localReady = false;

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

    await _initLocalNotifications();
    await _registerCurrentToken(apiClient);
    await _tokenRefreshSubscription?.cancel();
    _tokenRefreshSubscription = _instance.onTokenRefresh.listen((token) async {
      await _registerToken(apiClient, token);
    });

    // Subscribe unconditionally: while the app is foreground Android delivers
    // FCM to onMessage instead of the tray, so we surface a real notification
    // ourselves. (Backgrounded/killed pushes are shown by the OS directly.)
    await _foregroundSubscription?.cancel();
    _foregroundSubscription = FirebaseMessaging.onMessage.listen((message) {
      unawaited(_showForegroundMessage(message));
      // Keep the in-app banner too when a messenger is available, so users
      // already looking at the app get an inline cue alongside the pop-up.
      if (messenger != null) _showInAppBanner(messenger, message);
    });
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

  /// Initialize the local-notifications plugin and create the Android channel.
  /// Idempotent — safe to call on every (re)registration.
  Future<void> _initLocalNotifications() async {
    if (_localReady || kIsWeb) return;
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwinInit = DarwinInitializationSettings();
    await _localNotifications.initialize(
      const InitializationSettings(android: androidInit, iOS: darwinInit),
    );
    final android = _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      await android.createNotificationChannel(_alertChannel);
      // Android 13+: ensure POST_NOTIFICATIONS is granted for our own posts.
      await android.requestNotificationsPermission();
    }
    _localReady = true;
  }

  Future<void> _showForegroundMessage(RemoteMessage message) async {
    final notification = message.notification;
    final title = notification?.title ??
        'Erlang AI Vision · ${_severityTitle(message.data['severity'])}';
    final body = notification?.body ??
        message.data['summary']?.toString() ??
        message.data['event_type']?.toString() ??
        'A camera event needs review.';
    final eventId = message.data['event_id']?.toString();

    if (kIsWeb) {
      browser_notification.showBrowserNotification(
        title: title,
        body: body,
        eventId: eventId,
      );
      return;
    }

    await _initLocalNotifications();
    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        _alertChannel.id,
        _alertChannel.name,
        channelDescription: _alertChannel.description,
        importance: Importance.high,
        priority: Priority.high,
        category: AndroidNotificationCategory.message,
        icon: '@mipmap/ic_launcher',
      ),
      iOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    );

    // A stable id per event de-dupes repeats; fall back to time-ordered hash.
    final id = (eventId != null && eventId.isNotEmpty)
        ? eventId.hashCode & 0x7fffffff
        : message.hashCode & 0x7fffffff;
    await _localNotifications.show(
      id,
      title,
      body,
      details,
      payload: eventId,
    );
  }

  void _showInAppBanner(
    ScaffoldMessengerState messenger,
    RemoteMessage message,
  ) {
    final title = message.notification?.title ?? 'Security alert';
    final body = message.notification?.body ??
        message.data['summary']?.toString() ??
        message.data['event_type']?.toString() ??
        'A camera event needs review.';
    showEventAlert(
      messenger,
      title: title,
      body: body,
      tone: toneForSeverity(message.data['severity']?.toString()),
    );
  }

  String _severityTitle(Object? severity) {
    final s = (severity?.toString() ?? '').trim();
    if (s.isEmpty) return 'Alert';
    return '${s[0].toUpperCase()}${s.substring(1)} alert';
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
