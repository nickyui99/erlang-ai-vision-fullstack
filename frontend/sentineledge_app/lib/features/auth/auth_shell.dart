import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../design/app_colors.dart';
import '../../design/app_shadows.dart';
import '../../design/app_spacing.dart';
import '../../firebase_options.dart';
import '../../services/backend_auth_client.dart';
import '../../shared/console_widgets.dart';
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
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _restoreSession();
  }

  Future<void> _restoreSession() async {
    try {
      final backendUser = await _apiClient.currentUser();
      if (!mounted) return;
      setState(() {
        _backendUser = backendUser;
        _isLoading = false;
      });
      return;
    } catch (_) {
      // The backend session cookie may be absent after a fresh browser profile.
      // Firebase can still have a persisted Google user, so refresh backend auth.
    }

    try {
      if (DefaultFirebaseOptions.isConfigured) {
        final firebaseUser = FirebaseAuth.instance.currentUser;
        final idToken = await firebaseUser?.getIdToken();
        if (idToken != null && idToken.isNotEmpty) {
          final backendUser = await _authClient.loginWithFirebaseIdToken(
            idToken,
          );
          if (!mounted) return;
          setState(() => _backendUser = backendUser);
        }
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

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
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 980),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth >= 760;

                  return DecoratedBox(
                    decoration: BoxDecoration(
                      color: scheme.surface,
                      borderRadius: AppRadius.lgAll,
                      border: Border.all(color: scheme.outlineVariant),
                      boxShadow: AppShadows.overlay(
                        Theme.of(context).brightness,
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: AppRadius.lgAll,
                      child: wide
                          ? IntrinsicHeight(
                              child: Row(
                                children: [
                                  const Expanded(flex: 6, child: _BrandPanel()),
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
                                _LoginPanel(
                                  error: error,
                                  isLoading: isLoading,
                                  onSignIn: onSignIn,
                                ),
                              ],
                            ),
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
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.xxl),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.brandDeep, AppColors.primary],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.16),
              borderRadius: AppRadius.lgAll,
              border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
            ),
            child: const Icon(
              Icons.shield_outlined,
              color: Colors.white,
              size: 28,
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          Text(
            'SentinelEdge',
            style: theme.textTheme.displaySmall?.copyWith(color: Colors.white),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Command devices, natural-language agents, and edge sync from a focused security workspace.',
            style: theme.textTheme.titleMedium?.copyWith(
              color: Colors.white.withValues(alpha: 0.85),
              fontWeight: FontWeight.w400,
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          const Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
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
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xxl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Operator sign in', style: theme.textTheme.headlineSmall),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Use your Google account to start a backend session.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: AppSpacing.xl),
          if (!DefaultFirebaseOptions.isConfigured) ...[
            const AppBanner(
              tone: StatusTone.warning,
              icon: Icons.info_outline,
              text:
                  'Fill lib/firebase_options.dart with Firebase app settings before using Google sign-in.',
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          AppButton(
            label: 'Sign in with Google',
            loadingLabel: 'Signing in',
            icon: Icons.login,
            loading: isLoading,
            onPressed: onSignIn,
            expand: true,
          ),
          if (error != null) ...[
            const SizedBox(height: AppSpacing.md),
            AppBanner(text: error!),
          ],
          const SizedBox(height: AppSpacing.lg),
          Text(
            'Backend: ${BackendAuthClient.baseUrl}',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _SignalPill extends StatelessWidget {
  const _SignalPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: AppRadius.pillAll,
        border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: Colors.white),
          const SizedBox(width: 6),
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(color: Colors.white),
          ),
        ],
      ),
    );
  }
}
