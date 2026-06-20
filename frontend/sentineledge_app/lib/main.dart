import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'firebase_options.dart';
import 'services/backend_auth_client.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (DefaultFirebaseOptions.isConfigured) {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    if (!kIsWeb) {
      await GoogleSignIn.instance.initialize();
    }
  }
  runApp(const SentinelEdgeApp());
}

class SentinelEdgeApp extends StatelessWidget {
  const SentinelEdgeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SentinelEdge',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1F6F5B),
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFF5F7F4),
        useMaterial3: true,
      ),
      home: const AuthShell(),
    );
  }
}

class AuthShell extends StatefulWidget {
  const AuthShell({super.key});

  @override
  State<AuthShell> createState() => _AuthShellState();
}

class _AuthShellState extends State<AuthShell> {
  final BackendAuthClient _backendAuthClient = BackendAuthClient();
  BackendUser? _backendUser;
  String? _error;
  bool _isLoading = false;

  Future<void> _signIn() async {
    if (!DefaultFirebaseOptions.isConfigured) {
      setState(() {
        _error = 'Firebase options are not configured yet.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final userCredential = await _signInWithGoogle();
      final idToken = await userCredential.user?.getIdToken();
      if (idToken == null || idToken.isEmpty) {
        throw StateError('Firebase did not return an ID token.');
      }

      final backendUser = await _backendAuthClient.loginWithFirebaseIdToken(idToken);
      setState(() {
        _backendUser = backendUser;
      });
    } catch (error) {
      setState(() {
        _error = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<UserCredential> _signInWithGoogle() async {
    final auth = FirebaseAuth.instance;
    if (kIsWeb) {
      return auth.signInWithPopup(GoogleAuthProvider());
    }

    final googleUser = await GoogleSignIn.instance.authenticate();
    final googleAuth = await googleUser.authentication;
    final credential = GoogleAuthProvider.credential(
      idToken: googleAuth.idToken,
    );
    return auth.signInWithCredential(credential);
  }

  Future<void> _signOut() async {
    await FirebaseAuth.instance.signOut();
    if (!kIsWeb) {
      await GoogleSignIn.instance.signOut();
    }
    setState(() {
      _backendUser = null;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _ProductHeader(),
                  const SizedBox(height: 28),
                  if (!DefaultFirebaseOptions.isConfigured) const _SetupNotice(),
                  if (_backendUser != null) _SignedInPanel(user: _backendUser!, onSignOut: _signOut),
                  if (_backendUser == null)
                    FilledButton.icon(
                      onPressed: _isLoading ? null : _signIn,
                      icon: _isLoading
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.login),
                      label: Text(_isLoading ? 'Signing in' : 'Sign in with Google'),
                    ),
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      _error!,
                      style: TextStyle(color: Theme.of(context).colorScheme.error),
                    ),
                  ],
                  const SizedBox(height: 18),
                  Text(
                    'Backend: ${BackendAuthClient.baseUrl}',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ProductHeader extends StatelessWidget {
  const _ProductHeader();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.shield_outlined, size: 42, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: 16),
        Text(
          'SentinelEdge',
          style: Theme.of(context).textTheme.headlineLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Text(
          'Secure access for your edge surveillance workspace.',
          style: Theme.of(context).textTheme.bodyLarge,
        ),
      ],
    );
  }
}

class _SetupNotice extends StatelessWidget {
  const _SetupNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7E0),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE2B84C)),
      ),
      child: const Text('Fill lib/firebase_options.dart with Firebase app settings before using Google sign-in.'),
    );
  }
}

class _SignedInPanel extends StatelessWidget {
  const _SignedInPanel({required this.user, required this.onSignOut});

  final BackendUser user;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: CircleAvatar(
            child: Text(user.email.characters.first.toUpperCase()),
          ),
          title: Text(user.displayName ?? user.email),
          subtitle: Text('${user.role} - ${user.userId}'),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: onSignOut,
          icon: const Icon(Icons.logout),
          label: const Text('Sign out'),
        ),
      ],
    );
  }
}
