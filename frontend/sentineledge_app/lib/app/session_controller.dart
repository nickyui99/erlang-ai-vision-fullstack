import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../firebase_options.dart';
import '../services/backend_auth_client.dart';
import '../services/push_notification_service.dart';

/// Where the app is in the authentication lifecycle. The router uses this to
/// decide whether `/console/**` may render or should redirect to `/login`.
enum SessionStatus { restoring, signedIn, signedOut }

/// Owns the authenticated backend session and exposes it as a [Listenable] so
/// the [GoRouter] redirect guard can react to sign-in / sign-out. This lifts
/// the session state that used to live inside `AuthShell` up to the app root,
/// which is what lets routing (not a widget) gate the console.
class SessionController extends ChangeNotifier {
  SessionController({
    SentinelEdgeApiClient? apiClient,
    BackendAuthClient? authClient,
    PushNotificationService? pushNotifications,
  }) : apiClient = apiClient ?? SentinelEdgeApiClient(),
       _authClient = authClient ?? BackendAuthClient(),
       _pushNotifications = pushNotifications ?? PushNotificationService();

  final SentinelEdgeApiClient apiClient;
  final BackendAuthClient _authClient;
  final PushNotificationService _pushNotifications;

  SessionStatus _status = SessionStatus.restoring;
  BackendUser? _user;

  SessionStatus get status => _status;
  BackendUser? get user => _user;
  bool get isSignedIn => _status == SessionStatus.signedIn && _user != null;

  /// Restores a session on startup: first the backend cookie, then a persisted
  /// Firebase user if the cookie is gone. Always resolves [status] away from
  /// [SessionStatus.restoring] so the router can stop showing the splash.
  Future<void> restore() async {
    try {
      final backendUser = await apiClient.currentUser();
      _setSignedIn(backendUser);
      unawaited(_registerPushNotifications());
      return;
    } catch (_) {
      // The backend session cookie may be absent after a fresh browser profile.
      // Firebase can still have a persisted Google user, so refresh backend auth.
    }

    try {
      if (DefaultFirebaseOptions.isConfigured) {
        final firebaseUser = FirebaseAuth.instance.currentUser;
        if (firebaseUser != null) {
          final backendUser = await loginBackendWithFirebaseUser(firebaseUser);
          _setSignedIn(backendUser);
          unawaited(_registerPushNotifications());
          return;
        }
      }
    } catch (_) {
      // Fall through to signed-out; the login page surfaces auth errors.
    }
    _setSignedOut();
  }

  /// Called by the login page once Firebase has authenticated a user. Exchanges
  /// the Firebase ID token for a backend session and marks the app signed in.
  Future<BackendUser> completeSignInWithFirebaseUser(
    User firebaseUser, {
    ScaffoldMessengerState? messenger,
  }) async {
    final backendUser = await loginBackendWithFirebaseUser(firebaseUser);
    _setSignedIn(backendUser);
    unawaited(_registerPushNotifications(messenger: messenger));
    return backendUser;
  }

  Future<void> signOut() async {
    try {
      await _pushNotifications.deregisterForCurrentUser(apiClient);
      await _clearFirebaseSession();
      await _authClient.logout();
    } finally {
      _setSignedOut();
    }
  }

  /// Exchanges a Firebase ID token for a backend session, retrying once after a
  /// token refresh if the backend rejects it as stale.
  Future<BackendUser> loginBackendWithFirebaseUser(User firebaseUser) async {
    var idToken = await firebaseUser.getIdToken(true);
    if (idToken == null || idToken.isEmpty) {
      throw StateError('Firebase did not return an ID token.');
    }
    try {
      return await _authClient.loginWithFirebaseIdToken(idToken);
    } on BackendAuthException catch (error) {
      if (error.code != 'invalid_firebase_token') rethrow;
      await firebaseUser.reload();
      final refreshedUser = FirebaseAuth.instance.currentUser;
      idToken = await refreshedUser?.getIdToken(true);
      if (idToken == null || idToken.isEmpty) rethrow;
      return _authClient.loginWithFirebaseIdToken(idToken);
    }
  }

  Future<void> clearFirebaseSession() => _clearFirebaseSession();

  Future<void> _clearFirebaseSession() async {
    await FirebaseAuth.instance.signOut();
    if (!kIsWeb) {
      await GoogleSignIn.instance.signOut();
    }
  }

  Future<void> _registerPushNotifications({
    ScaffoldMessengerState? messenger,
  }) async {
    try {
      await _pushNotifications.registerForCurrentUser(
        apiClient,
        messenger: messenger,
      );
    } catch (_) {
      // Push registration is best-effort; sign-in must not fail because of it.
    }
  }

  void _setSignedIn(BackendUser user) {
    _user = user;
    _status = SessionStatus.signedIn;
    notifyListeners();
  }

  void _setSignedOut() {
    _user = null;
    _status = SessionStatus.signedOut;
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(_pushNotifications.dispose());
    super.dispose();
  }
}

/// Exposes the [SessionController] to the widget tree and rebuilds dependents
/// when the session changes.
class SessionScope extends InheritedNotifier<SessionController> {
  const SessionScope({
    required SessionController controller,
    required super.child,
    super.key,
  }) : super(notifier: controller);

  static SessionController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<SessionScope>();
    assert(scope?.notifier != null, 'No SessionScope found in context');
    return scope!.notifier!;
  }
}
