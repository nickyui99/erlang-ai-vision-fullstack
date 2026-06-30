import 'package:flutter/material.dart';

import '../design/app_theme.dart';
import '../features/auth/auth_shell.dart';
import 'theme_mode_controller.dart';

class SentinelEdgeApp extends StatefulWidget {
  const SentinelEdgeApp({super.key});

  @override
  State<SentinelEdgeApp> createState() => _SentinelEdgeAppState();
}

class _SentinelEdgeAppState extends State<SentinelEdgeApp> {
  final ThemeModeController _themeModeController = ThemeModeController();

  @override
  void dispose() {
    _themeModeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppThemeModeScope(
      controller: _themeModeController,
      child: ValueListenableBuilder<ThemeMode>(
        valueListenable: _themeModeController,
        builder: (context, themeMode, _) {
          return MaterialApp(
            title: 'Erlang AI Vision',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light(),
            darkTheme: AppTheme.dark(),
            themeMode: themeMode,
            home: const AuthShell(),
          );
        },
      ),
    );
  }
}
