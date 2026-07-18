import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../design/app_theme.dart';
import 'app_router.dart';
import 'session_controller.dart';
import 'theme_mode_controller.dart';

/// Canonical route paths, kept as constants so navigation call sites don't
/// hard-code strings. The URL structure is defined in [AppRouter].
abstract final class AppRoutes {
  static const landing = '/';
  static const architecture = '/architecture';
  static const qwen = '/qwen';
  static const login = '/login';
  static const console = '/console';
  static const consoleCameras = '/console/cameras';
  static const consoleOverview = '/console/overview';
  static const consoleAgents = '/console/agents';
  static const consoleEvents = '/console/events';
  static const consoleSettings = '/console/settings';
}

class ErlangVisionApp extends StatefulWidget {
  const ErlangVisionApp({
    required this.session,
    required this.scaffoldMessengerKey,
    super.key,
  });

  final SessionController session;
  final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey;

  @override
  State<ErlangVisionApp> createState() => _ErlangVisionAppState();
}

class _ErlangVisionAppState extends State<ErlangVisionApp> {
  final ThemeModeController _themeModeController = ThemeModeController();
  late final GoRouter _router = AppRouter.build(widget.session);

  @override
  void dispose() {
    _themeModeController.dispose();
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SessionScope(
      controller: widget.session,
      child: AppThemeModeScope(
        controller: _themeModeController,
        child: ValueListenableBuilder<ThemeMode>(
          valueListenable: _themeModeController,
          builder: (context, themeMode, _) {
            return MaterialApp.router(
              scaffoldMessengerKey: widget.scaffoldMessengerKey,
              title: 'Erlang AI Vision',
              debugShowCheckedModeBanner: false,
              theme: AppTheme.light(),
              darkTheme: AppTheme.dark(),
              themeMode: themeMode,
              routerConfig: _router,
            );
          },
        ),
      ),
    );
  }
}
