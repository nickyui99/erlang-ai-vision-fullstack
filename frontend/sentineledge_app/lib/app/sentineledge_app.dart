import 'package:flutter/material.dart';

import '../design/app_theme.dart';
import '../features/auth/auth_shell.dart';

class SentinelEdgeApp extends StatelessWidget {
  const SentinelEdgeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SentinelEdge',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      home: const AuthShell(),
    );
  }
}
