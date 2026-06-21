import 'package:flutter/material.dart';

import '../features/auth/auth_shell.dart';
import 'sentineledge_theme.dart';

class SentinelEdgeApp extends StatelessWidget {
  const SentinelEdgeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SentinelEdge',
      debugShowCheckedModeBanner: false,
      theme: SentinelEdgeTheme.light(),
      darkTheme: SentinelEdgeTheme.dark(),
      themeMode: ThemeMode.system,
      home: const AuthShell(),
    );
  }
}
