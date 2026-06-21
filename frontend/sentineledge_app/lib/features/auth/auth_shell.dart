import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../firebase_options.dart';
import '../../services/backend_auth_client.dart';
import '../dashboard/workspace_view.dart';

class AuthShell extends StatefulWidget {
  const AuthShell({super.key});

  @override
  State<AuthShell> createState() => _AuthShellState();
}

class _AuthShellState extends State<AuthShell> {
  final BackendAuthClient _authClient = BackendAuthClient();
  final SentinelEdgeApiClient _apiClient = SentinelEdgeApiClient();
  BackendUser? _backendUser;
  String? _error;
  bool _isLoading = false;

  Future<void> _signIn() async {
    if (!DefaultFirebaseOptions.isConfigured) {
      setState(() => _error = 'Firebase options are not configured yet.');
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
      final backendUser = await _authClient.loginWithFirebaseIdToken(idToken);
      if (!mounted) return;
      setState(() => _backendUser = backendUser);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<UserCredential> _signInWithGoogle() async {
    final auth = FirebaseAuth.instance;
    if (kIsWeb) {
      return auth.signInWithPopup(GoogleAuthProvider());
    }

    final googleUser = await GoogleSignIn.instance.authenticate();
    final googleAuth = googleUser.authentication;
    final credential = GoogleAuthProvider.credential(
      idToken: googleAuth.idToken,
    );
    return auth.signInWithCredential(credential);
  }

  Future<void> _signOut() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      await _authClient.logout();
      await FirebaseAuth.instance.signOut();
      if (!kIsWeb) {
        await GoogleSignIn.instance.signOut();
      }
      if (!mounted) return;
      setState(() => _backendUser = null);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = _backendUser;
    return user == null
        ? SignInView(error: _error, isLoading: _isLoading, onSignIn: _signIn)
        : WorkspaceView(user: user, apiClient: _apiClient, onSignOut: _signOut);
  }
}

class SignInView extends StatelessWidget {
  const SignInView({
    required this.error,
    required this.isLoading,
    required this.onSignIn,
    super.key,
  });

  final String? error;
  final bool isLoading;
  final VoidCallback onSignIn;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 960),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth >= 760;

                  return Container(
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerLowest,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: scheme.outlineVariant),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: wide
                        ? IntrinsicHeight(
                            child: Row(
                              children: [
                                const Expanded(flex: 6, child: _BrandPanel()),
                                const VerticalDivider(width: 1),
                                Expanded(
                                  flex: 4,
                                  child: _LoginPanel(
                                    error: error,
                                    isLoading: isLoading,
                                    onSignIn: onSignIn,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const _BrandPanel(),
                              const Divider(height: 1),
                              _LoginPanel(
                                error: error,
                                isLoading: isLoading,
                                onSignIn: onSignIn,
                              ),
                            ],
                          ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BrandPanel extends StatelessWidget {
  const _BrandPanel();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(28),
      color: scheme.surfaceContainerLow,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              Icons.shield_outlined,
              color: scheme.onPrimaryContainer,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'SentinelEdge',
            style: Theme.of(context).textTheme.displaySmall?.copyWith(
              fontWeight: FontWeight.w800,
              height: 1,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Command devices, natural-language agents, and edge sync from a focused security workspace.',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: scheme.onSurfaceVariant,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 28),
          const Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _SignalPill(icon: Icons.videocam_outlined, label: 'Devices'),
              _SignalPill(icon: Icons.radar_outlined, label: 'Agents'),
              _SignalPill(icon: Icons.hub_outlined, label: 'Edge sync'),
            ],
          ),
        ],
      ),
    );
  }
}

class _LoginPanel extends StatelessWidget {
  const _LoginPanel({
    required this.error,
    required this.isLoading,
    required this.onSignIn,
  });

  final String? error;
  final bool isLoading;
  final VoidCallback onSignIn;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Operator sign in',
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text(
            'Use your Google account to start a backend session.',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 20),
          if (!DefaultFirebaseOptions.isConfigured) const _SetupNotice(),
          FilledButton.icon(
            onPressed: isLoading ? null : onSignIn,
            icon: isLoading
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.login),
            label: Text(isLoading ? 'Signing in' : 'Sign in with Google'),
          ),
          if (error != null) ...[
            const SizedBox(height: 14),
            _InlineAlert(text: error!, isError: true),
          ],
          const SizedBox(height: 18),
          Text(
            'Backend: ${BackendAuthClient.baseUrl}',
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _SetupNotice extends StatelessWidget {
  const _SetupNotice();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(bottom: 14),
      child: _InlineAlert(
        text:
            'Fill lib/firebase_options.dart with Firebase app settings before using Google sign-in.',
        isError: false,
      ),
    );
  }
}

class _InlineAlert extends StatelessWidget {
  const _InlineAlert({required this.text, required this.isError});

  final String text;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = isError ? scheme.error : const Color(0xFFB68416);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Text(text, style: TextStyle(color: color)),
    );
  }
}

class _SignalPill extends StatelessWidget {
  const _SignalPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: scheme.primary),
          const SizedBox(width: 6),
          Text(label, style: Theme.of(context).textTheme.labelMedium),
        ],
      ),
    );
  }
}
