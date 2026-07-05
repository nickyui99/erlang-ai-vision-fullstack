import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/login_page.dart';
import '../features/dashboard/console_page.dart';
import '../features/dashboard/workspace_view.dart';
import '../features/landing/landing_page.dart';
import '../shared/not_found_page.dart';
import 'session_controller.dart';

/// Declarative URL map for the app. Every page — the landing sections, login,
/// each console tab, and each selected camera/event — has its own address, so
/// deep links, refresh, and browser back/forward all work. The [session]
/// drives an auth [redirect] guard so `/console/**` is gated by routing rather
/// than inside a widget.
abstract final class AppRouter {
  // Landing sections share one persistent page: switching between them scrolls
  // the same LandingPage instead of rebuilding it.
  static const _landingPageKey = ValueKey<String>('landing');
  // All console tabs + event selection share one persistent page so the
  // WorkspaceView (realtime stream, loaded devices/agents/events) is reused.
  static const _consolePageKey = ValueKey<String>('console');

  static GoRouter build(SessionController session) {
    return GoRouter(
      initialLocation: '/',
      refreshListenable: session,
      redirect: (context, state) => _redirect(session, state),
      errorBuilder: (context, state) =>
          NotFoundPage(location: state.uri.toString()),
      routes: [
        GoRoute(
          path: '/',
          pageBuilder: (context, state) =>
              _landing(context, LandingSection.hero),
        ),
        GoRoute(
          path: '/architecture',
          pageBuilder: (context, state) =>
              _landing(context, LandingSection.architecture),
        ),
        GoRoute(
          path: '/qwen',
          pageBuilder: (context, state) =>
              _landing(context, LandingSection.qwen),
        ),
        GoRoute(
          path: '/login',
          builder: (context, state) => const LoginPage(),
        ),
        GoRoute(
          path: '/console',
          redirect: (context, state) =>
              state.matchedLocation == '/console' ? '/console/cameras' : null,
        ),
        // Cameras tab, with the full-screen device detail stacked on top.
        GoRoute(
          path: '/console/cameras',
          pageBuilder: (context, state) =>
              _console(WorkspaceSection.cameras),
          routes: [
            GoRoute(
              path: ':deviceId',
              pageBuilder: (context, state) {
                final deviceId = state.pathParameters['deviceId']!;
                return MaterialPage(
                  key: ValueKey('camera-$deviceId'),
                  child: DeviceControlPage(deviceId: deviceId),
                );
              },
            ),
          ],
        ),
        GoRoute(
          path: '/console/overview',
          pageBuilder: (context, state) =>
              _console(WorkspaceSection.overview),
        ),
        GoRoute(
          path: '/console/agents',
          pageBuilder: (context, state) => _console(WorkspaceSection.agents),
        ),
        // Events tab. The selected event is a sibling route (not nested) so it
        // updates the same console page in place rather than stacking.
        GoRoute(
          path: '/console/events',
          pageBuilder: (context, state) => _console(WorkspaceSection.events),
        ),
        GoRoute(
          path: '/console/events/:eventId',
          pageBuilder: (context, state) => _console(
            WorkspaceSection.events,
            selectedEventId: state.pathParameters['eventId'],
          ),
        ),
        GoRoute(
          path: '/console/settings',
          pageBuilder: (context, state) =>
              _console(WorkspaceSection.settings),
        ),
      ],
    );
  }

  static String? _redirect(SessionController session, GoRouterState state) {
    final status = session.status;
    // Still checking for an existing session — let the current route render its
    // loading state; this guard re-runs when the status resolves.
    if (status == SessionStatus.restoring) return null;

    final location = state.matchedLocation;
    final atLogin = location == '/login';
    final atConsole = location == '/console' || location.startsWith('/console/');
    final signedIn = status == SessionStatus.signedIn;

    if (!signedIn && atConsole) {
      final from = Uri.encodeComponent(state.uri.toString());
      return '/login?from=$from';
    }
    if (signedIn && atLogin) {
      final from = state.uri.queryParameters['from'];
      if (from != null && from.startsWith('/console')) return from;
      return '/console/cameras';
    }
    return null;
  }

  static MaterialPage<void> _landing(
    BuildContext context,
    LandingSection section,
  ) {
    return MaterialPage<void>(
      key: _landingPageKey,
      child: LandingPage(
        initialSection: section,
        onLaunchDemo: () => context.go('/console'),
        onLogin: () => context.go('/login'),
        onViewArchitecture: () => context.go('/architecture'),
        onViewQwen: () => context.go('/qwen'),
      ),
    );
  }

  static MaterialPage<void> _console(
    WorkspaceSection section, {
    String? selectedEventId,
  }) {
    return MaterialPage<void>(
      key: _consolePageKey,
      child: ConsolePage(
        section: section,
        selectedEventId: selectedEventId,
      ),
    );
  }
}
