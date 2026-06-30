import 'dart:math' as math;

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
        if (firebaseUser != null) {
          final backendUser = await _loginBackendWithFirebaseUser(firebaseUser);
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

  Future<void> _signInWithGoogleProvider() async {
    if (!DefaultFirebaseOptions.isConfigured) {
      setState(() => _error = 'Firebase options are not configured yet.');
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      await _clearFirebaseSession();
      final userCredential = await _signInWithGoogle();
      final firebaseUser = userCredential.user;
      if (firebaseUser == null) {
        throw StateError('Firebase did not return a signed-in user.');
      }
      final backendUser = await _loginBackendWithFirebaseUser(firebaseUser);
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
  Future<void> _signInWithEmailPassword(String email, String password) async {
    if (!DefaultFirebaseOptions.isConfigured) {
      setState(() => _error = 'Firebase options are not configured yet.');
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      await _clearFirebaseSession();
      final credential = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      final firebaseUser = credential.user;
      if (firebaseUser == null) {
        throw StateError('Firebase did not return a signed-in user.');
      }
      final backendUser = await _loginBackendWithFirebaseUser(firebaseUser);
      if (!mounted) return;
      setState(() => _backendUser = backendUser);
    } on BackendAuthException catch (error) {
      if (!mounted) return;
      if (error.code == 'email_not_verified') {
        final user = FirebaseAuth.instance.currentUser;
        await user?.sendEmailVerification();
        setState(
          () => _error =
              'Please verify your email first. A verification email was sent.',
        );
      } else {
        setState(() => _error = error.toString());
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

  Future<void> _createEmailPasswordAccount(String email, String password) async {
    if (!DefaultFirebaseOptions.isConfigured) {
      setState(() => _error = 'Firebase options are not configured yet.');
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      await _clearFirebaseSession();
      final credential = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(email: email, password: password);
      await credential.user?.sendEmailVerification();
      await FirebaseAuth.instance.signOut();
      if (!mounted) return;
      setState(
        () => _error =
            'Account created. Check your inbox and verify your email before signing in.',
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<BackendUser> _loginBackendWithFirebaseUser(User firebaseUser) async {
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

  Future<void> _clearFirebaseSession() async {
    await FirebaseAuth.instance.signOut();
    if (!kIsWeb) {
      await GoogleSignIn.instance.signOut();
    }
  }

  Future<UserCredential> _signInWithGoogle() async {
    final auth = FirebaseAuth.instance;
    if (kIsWeb) {
      final provider = GoogleAuthProvider()
        ..setCustomParameters({'prompt': 'select_account'});
      return auth.signInWithPopup(provider);
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
      await _clearFirebaseSession();
      await _authClient.logout();
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
        ? SignInView(
            error: _error,
            isLoading: _isLoading,
            onGoogleSignIn: _signInWithGoogleProvider,
            onEmailSignIn: _signInWithEmailPassword,
            onEmailCreate: _createEmailPasswordAccount,
          )
        : WorkspaceView(user: user, apiClient: _apiClient, onSignOut: _signOut);
  }
}

class SignInView extends StatelessWidget {
  const SignInView({
    required this.error,
    required this.isLoading,
    required this.onGoogleSignIn,
    required this.onEmailSignIn,
    required this.onEmailCreate,
    super.key,
  });

  final String? error;
  final bool isLoading;
  final VoidCallback onGoogleSignIn;
  final Future<void> Function(String email, String password) onEmailSignIn;
  final Future<void> Function(String email, String password) onEmailCreate;

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
                          ? SizedBox(
                              height: 560,
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  const Expanded(flex: 6, child: _BrandPanel()),
                                  Expanded(
                                    flex: 4,
                                    child: _LoginPanel(
                                      error: error,
                                      isLoading: isLoading,
                                      onGoogleSignIn: onGoogleSignIn,
                                      onEmailSignIn: onEmailSignIn,
                                      onEmailCreate: onEmailCreate,
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
                                  onGoogleSignIn: onGoogleSignIn,
                                  onEmailSignIn: onEmailSignIn,
                                  onEmailCreate: onEmailCreate,
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

class _BrandPanel extends StatefulWidget {
  const _BrandPanel();

  @override
  State<_BrandPanel> createState() => _BrandPanelState();
}

class _BrandPanelState extends State<_BrandPanel>
    with SingleTickerProviderStateMixin {
  late final AnimationController _motion;

  @override
  void initState() {
    super.initState();
    _motion = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5),
    )..repeat();
  }

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const logoAsset = 'assets/brand/erlang-ai-vision-icon.png';
    return AnimatedBuilder(
      animation: _motion,
      builder: (context, child) {
        final phase = _motion.value * math.pi * 2;
        final drift = math.sin(phase) * 0.28;
        final lift = math.cos(phase) * 0.18;
        return Container(
          width: double.infinity,
          constraints: const BoxConstraints(minHeight: 430),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: const [
                Color(0xFF8F120B),
                AppColors.primary,
                AppColors.accentOrange,
                Color(0xFFEF2F22),
              ],
              stops: const [0, 0.42, 0.72, 1],
              begin: Alignment(-1 + drift, -1 + lift),
              end: Alignment(1 - drift, 1 - lift),
            ),
          ),
          child: Stack(
            children: [
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.white.withValues(alpha: 0.12),
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.18),
                      ],
                      stops: const [0, 0.48, 1],
                      begin: Alignment(-0.8 + drift, -1),
                      end: Alignment(0.8 - drift, 1),
                    ),
                  ),
                ),
              ),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: Alignment(0.75 * math.sin(phase), -0.55),
                      radius: 0.92 + (0.08 * math.cos(phase)),
                      colors: [
                        Colors.white.withValues(alpha: 0.24),
                        Colors.white.withValues(alpha: 0.04),
                        Colors.transparent,
                      ],
                      stops: const [0, 0.38, 1],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(AppSpacing.xxl),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 76,
                      height: 76,
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.94),
                        borderRadius: AppRadius.lgAll,
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.54),
                          width: 2,
                        ),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Image.asset(logoAsset, fit: BoxFit.contain),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    Text(
                      'Erlang AI Vision',
                      style: theme.textTheme.displaySmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      'Camera intelligence for live monitoring, edge control, and verified security events.',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: Colors.white.withValues(alpha: 0.9),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    const Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.sm,
                      children: [
                        _SignalPill(
                          icon: Icons.videocam_outlined,
                          label: 'Live cameras',
                        ),
                        _SignalPill(
                          icon: Icons.radar_outlined,
                          label: 'AI agents',
                        ),
                        _SignalPill(
                          icon: Icons.hub_outlined,
                          label: 'Edge control',
                        ),
                        _SignalPill(
                          icon: Icons.verified_outlined,
                          label: 'Verified alerts',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _LoginPanel extends StatefulWidget {
  const _LoginPanel({
    required this.error,
    required this.isLoading,
    required this.onGoogleSignIn,
    required this.onEmailSignIn,
    required this.onEmailCreate,
  });

  final String? error;
  final bool isLoading;
  final VoidCallback onGoogleSignIn;
  final Future<void> Function(String email, String password) onEmailSignIn;
  final Future<void> Function(String email, String password) onEmailCreate;

  @override
  State<_LoginPanel> createState() => _LoginPanelState();
}

class _LoginPanelState extends State<_LoginPanel> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _creatingAccount = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submitEmailPassword() async {
    if (!_formKey.currentState!.validate()) return;
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    if (_creatingAccount) {
      await widget.onEmailCreate(email, password);
    } else {
      await widget.onEmailSignIn(email, password);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xxl),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Operator sign in', style: theme.textTheme.headlineSmall),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Access your camera workspace with Google or email/password.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: AppSpacing.xl),
            if (!DefaultFirebaseOptions.isConfigured) ...[
              const AppBanner(
                tone: StatusTone.warning,
                icon: Icons.info_outline,
                text:
                    'Fill config/firebase.json and launch Flutter with --dart-define-from-file before signing in.',
              ),
              const SizedBox(height: AppSpacing.md),
            ],
            TextFormField(
              controller: _emailController,
              enabled: !widget.isLoading,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              decoration: const InputDecoration(
                labelText: 'Email',
                prefixIcon: Icon(Icons.email_outlined),
              ),
              validator: (value) {
                final email = value?.trim() ?? '';
                if (email.isEmpty) return 'Email is required.';
                if (!email.contains('@')) return 'Enter a valid email.';
                return null;
              },
            ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              controller: _passwordController,
              enabled: !widget.isLoading,
              obscureText: _obscurePassword,
              autofillHints: const [AutofillHints.password],
              decoration: InputDecoration(
                labelText: 'Password',
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  tooltip: _obscurePassword ? 'Show password' : 'Hide password',
                  icon: Icon(
                    _obscurePassword
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                  onPressed: widget.isLoading
                      ? null
                      : () => setState(
                            () => _obscurePassword = !_obscurePassword,
                          ),
                ),
              ),
              validator: (value) {
                final password = value ?? '';
                if (password.isEmpty) return 'Password is required.';
                if (_creatingAccount && password.length < 6) {
                  return 'Use at least 6 characters.';
                }
                return null;
              },
              onFieldSubmitted: (_) => _submitEmailPassword(),
            ),
            const SizedBox(height: AppSpacing.lg),
            AppButton(
              label: _creatingAccount ? 'Create account' : 'Sign in with email',
              loadingLabel: _creatingAccount ? 'Creating account' : 'Signing in',
              icon: _creatingAccount ? Icons.person_add_alt : Icons.login,
              loading: widget.isLoading,
              onPressed: _submitEmailPassword,
              expand: true,
            ),
            const SizedBox(height: AppSpacing.sm),
            TextButton(
              onPressed: widget.isLoading
                  ? null
                  : () => setState(() => _creatingAccount = !_creatingAccount),
              child: Text(
                _creatingAccount
                    ? 'Already verified? Sign in instead'
                    : 'Need an account? Create one',
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                const Expanded(child: Divider()),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                  child: Text('or', style: theme.textTheme.bodySmall),
                ),
                const Expanded(child: Divider()),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            AppButton(
              label: 'Sign in with Google',
              loadingLabel: 'Signing in',
              icon: Icons.login,
              variant: AppButtonVariant.secondary,
              loading: widget.isLoading,
              onPressed: widget.onGoogleSignIn,
              expand: true,
            ),
            if (widget.error != null) ...[
              const SizedBox(height: AppSpacing.md),
              AppBanner(text: widget.error!),
            ],
            const SizedBox(height: AppSpacing.lg),
            Text(
              'Backend: ${BackendAuthClient.baseUrl}',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
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

