import 'dart:async';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/backend_config.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../game/ui/mascot.dart';
import 'auth_callback.dart';
import 'auth_messages.dart';
import 'auth_providers.dart';
import 'oauth/oauth_buttons.dart';

enum AuthMode { login, register }

/// `/login`: one screen with a Log in / Sign up toggle, a mascot welcome,
/// validation, loading and friendly errors. Navigation after success is done
/// by the router's auth gate.
class LoginScreen extends ConsumerStatefulWidget {
  final AuthMode initialMode;

  /// Email confirmation outcome from the `/auth-callback` deep link.
  final AuthCallbackResult? callback;

  const LoginScreen({
    super.key,
    this.initialMode = AuthMode.login,
    this.callback,
  });

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();

  late AuthMode _mode = widget.initialMode;
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  /// Email awaiting confirmation after sign-up.
  String? _confirmationSentTo;

  /// Provider whose sign-in is running (spinner on its button).
  OAuthProvider? _busyProvider;
  StreamSubscription<OAuthCredential>? _webCredentials;

  bool get _isRegister => _mode == AuthMode.register;

  @override
  void initState() {
    super.initState();
    // Google on web: sign-ins come from Google's own rendered button.
    _webCredentials = ref
        .read(oauthSignInProvider)
        .webCredentials
        .listen(
          (c) => _runOAuth(c.provider, () async {
            await ref
                .read(authControllerProvider.notifier)
                .signInWithCredential(c);
            return true;
          }),
          onError: (Object e) {
            if (mounted) {
              setState(
                () => _error = friendlyAuthError(
                  e,
                  provider: OAuthProvider.google,
                ),
              );
            }
          },
        );
  }

  Future<void> _oauth(OAuthProvider provider) {
    final auth = ref.read(authControllerProvider.notifier);
    return _runOAuth(
      provider,
      () => switch (provider) {
        OAuthProvider.google => auth.signInWithGoogle(),
        OAuthProvider.apple => auth.signInWithApple(),
      },
    );
  }

  /// Shared busy/error handling; a cancelled sign-in shows nothing.
  Future<void> _runOAuth(
    OAuthProvider provider,
    Future<bool> Function() run,
  ) async {
    if (_busy) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _busyProvider = provider;
      _error = null;
      _confirmationSentTo = null;
    });
    try {
      await run();
    } catch (e) {
      debugPrint(
        'OAuth sign-in (${provider.wire}) failed: ${e.runtimeType}: $e',
      );
      if (mounted) {
        setState(() => _error = friendlyAuthError(e, provider: provider));
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _busyProvider = null;
        });
      }
    }
  }

  @override
  void dispose() {
    _webCredentials?.cancel();
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  void _switchMode(AuthMode mode) {
    if (_busy || mode == _mode) return;
    setState(() {
      _mode = mode;
      _error = null;
      _confirmationSentTo = null;
    });
    _formKey.currentState?.reset();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _error = null;
      _confirmationSentTo = null;
    });
    final auth = ref.read(authControllerProvider.notifier);
    try {
      if (_isRegister) {
        final result = await auth.register(
          email: _email.text,
          password: _password.text,
          displayName: _name.text.trim().isEmpty ? null : _name.text.trim(),
        );
        if (!mounted) return;
        if (result.needsConfirmation) {
          setState(() {
            _confirmationSentTo = _email.text.trim();
            _mode = AuthMode.login;
            _password.clear();
            _confirm.clear();
          });
        }
      } else {
        await auth.login(email: _email.text, password: _password.text);
      }
    } catch (e) {
      if (mounted) setState(() => _error = friendlyAuthError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final configured = ref.watch(backendConfigProvider).isConfigured;
    final authState = ref.watch(authControllerProvider);
    final signedOutReason = authState is SignedOut ? authState.reason : null;
    final callback = widget.callback;

    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              scheme.primary.withValues(alpha: 0.18),
              AppColors.sunshine.withValues(alpha: 0.12),
              scheme.surface,
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _Welcome(isRegister: _isRegister),
                    const SizedBox(height: 20),
                    if (!configured) ...[
                      const _Banner(
                        key: ValueKey('auth-not-configured'),
                        emoji: '🔧',
                        color: AppColors.flame,
                        title: 'Server not configured',
                        message: notConfiguredMessage,
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (callback != null && _confirmationSentTo == null) ...[
                      _Banner(
                        key: ValueKey(
                          callback.confirmed
                              ? 'auth-callback-confirmed'
                              : 'auth-callback-error',
                        ),
                        emoji: callback.emoji,
                        color: callback.confirmed
                            ? AppColors.mint
                            : AppColors.coral,
                        title: callback.title,
                        message: callback.message,
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (signedOutReason != null &&
                        callback == null &&
                        _error == null &&
                        _confirmationSentTo == null) ...[
                      _Banner(
                        key: const ValueKey('auth-signed-out-reason'),
                        emoji:
                            signedOutReason ==
                                AuthController.accountDeletedMessage
                            ? '👋'
                            : '⏳',
                        color: AppColors.sky,
                        message: signedOutReason,
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (_confirmationSentTo != null) ...[
                      _Banner(
                        key: const ValueKey('auth-needs-confirmation'),
                        emoji: '📬',
                        color: AppColors.mint,
                        title: 'Check your inbox!',
                        message:
                            'We sent a confirmation link to '
                            '$_confirmationSentTo. Tap it, then log in here.',
                      ),
                      const SizedBox(height: 12),
                    ],
                    _formCard(theme, configured),
                    ..._notConfiguredHint(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _formCard(ThemeData theme, bool configured) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ..._socialButtons(configured),
              SegmentedButton<AuthMode>(
                key: const ValueKey('auth-mode'),
                segments: const [
                  ButtonSegment(
                    value: AuthMode.login,
                    label: Text('Log in', key: ValueKey('auth-mode-login')),
                    icon: Icon(Icons.login_rounded),
                  ),
                  ButtonSegment(
                    value: AuthMode.register,
                    label: Text('Sign up', key: ValueKey('auth-mode-register')),
                    icon: Icon(Icons.auto_awesome_rounded),
                  ),
                ],
                selected: {_mode},
                showSelectedIcon: false,
                onSelectionChanged: _busy ? null : (s) => _switchMode(s.first),
              ),
              const SizedBox(height: 20),
              AnimatedSize(
                duration: const Duration(milliseconds: 200),
                alignment: Alignment.topCenter,
                child: _isRegister
                    ? Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: TextFormField(
                          key: const ValueKey('auth-name'),
                          controller: _name,
                          enabled: !_busy,
                          textInputAction: TextInputAction.next,
                          textCapitalization: TextCapitalization.words,
                          maxLength: 100,
                          decoration: const InputDecoration(
                            labelText: 'Hero name (optional)',
                            prefixIcon: Icon(Icons.face_rounded),
                            counterText: '',
                          ),
                        ),
                      )
                    : const SizedBox(width: double.infinity),
              ),
              TextFormField(
                key: const ValueKey('auth-email'),
                controller: _email,
                enabled: !_busy,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                autocorrect: false,
                autofillHints: const [AutofillHints.email],
                decoration: const InputDecoration(
                  labelText: 'Email',
                  prefixIcon: Icon(Icons.alternate_email_rounded),
                ),
                validator: validateEmail,
              ),
              const SizedBox(height: 14),
              TextFormField(
                key: const ValueKey('auth-password'),
                controller: _password,
                enabled: !_busy,
                obscureText: _obscure,
                textInputAction: _isRegister
                    ? TextInputAction.next
                    : TextInputAction.done,
                autofillHints: [
                  _isRegister
                      ? AutofillHints.newPassword
                      : AutofillHints.password,
                ],
                onFieldSubmitted: _isRegister ? null : (_) => _submit(),
                decoration: InputDecoration(
                  labelText: 'Password',
                  prefixIcon: const Icon(Icons.lock_rounded),
                  helperText: _isRegister ? 'At least 6 characters' : null,
                  suffixIcon: IconButton(
                    tooltip: _obscure ? 'Show password' : 'Hide password',
                    icon: Icon(
                      _obscure
                          ? Icons.visibility_rounded
                          : Icons.visibility_off_rounded,
                    ),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
                validator: (v) => validatePassword(v, isRegister: _isRegister),
              ),
              if (_isRegister) ...[
                const SizedBox(height: 14),
                TextFormField(
                  key: const ValueKey('auth-confirm'),
                  controller: _confirm,
                  enabled: !_busy,
                  obscureText: _obscure,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _submit(),
                  decoration: const InputDecoration(
                    labelText: 'Confirm password',
                    prefixIcon: Icon(Icons.lock_outline_rounded),
                  ),
                  validator: (v) =>
                      v != _password.text ? "Passwords don't match" : null,
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 16),
                _Banner(
                  key: const ValueKey('auth-error'),
                  emoji: '😬',
                  color: AppColors.coral,
                  message: _error!,
                ),
              ],
              const SizedBox(height: 20),
              FilledButton(
                key: const ValueKey('auth-submit'),
                onPressed: (_busy || !configured) ? null : _submit,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                ),
                child: _busy
                    ? const SizedBox(
                        key: ValueKey('auth-loading'),
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 3),
                      )
                    : Text(
                        _isRegister ? 'Start my quest' : 'Continue my quest',
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

extension on _LoginScreenState {
  /// Google / Apple buttons and the "or" divider; nothing (or a debug-only
  /// hint) when neither provider is configured in this build.
  /// Debug builds only, under the form: why there are no social buttons.
  List<Widget> _notConfiguredHint() {
    final oauth = ref.watch(oauthSignInProvider);
    if (!kDebugMode ||
        oauth.isAvailable(OAuthProvider.google) ||
        oauth.isAvailable(OAuthProvider.apple)) {
      return const [];
    }
    return [
      const SizedBox(height: 14),
      Text(
        'Debug: Google & Apple sign-in are not configured '
        '(lib/core/config/env.dart, see the README).',
        key: const ValueKey('oauth-not-configured-hint'),
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    ];
  }

  List<Widget> _socialButtons(bool configured) {
    final oauth = ref.watch(oauthSignInProvider);
    final google = oauth.isAvailable(OAuthProvider.google);
    final apple = oauth.isAvailable(OAuthProvider.apple);
    final enabled = !_busy && configured;
    final buttons = <Widget>[
      if (apple)
        AppleSignInButton(
          key: const ValueKey('oauth-apple'),
          busy: _busyProvider == OAuthProvider.apple,
          onPressed: enabled ? () => _oauth(OAuthProvider.apple) : null,
        ),
      if (google)
        oauth.googleWebButton() ??
            GoogleSignInButton(
              key: const ValueKey('oauth-google'),
              busy: _busyProvider == OAuthProvider.google,
              onPressed: enabled ? () => _oauth(OAuthProvider.google) : null,
            ),
    ];
    if (buttons.isEmpty) return const [];
    return [
      for (var i = 0; i < buttons.length; i++) ...[
        if (i > 0) const SizedBox(height: 12),
        buttons[i],
      ],
      const OrDivider(key: ValueKey('oauth-or-divider')),
    ];
  }
}

/// Email validator (shared with tests).
String? validateEmail(String? value) {
  final v = value?.trim() ?? '';
  if (v.isEmpty) return 'Enter your email';
  if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v)) {
    return "That doesn't look like an email";
  }
  return null;
}

/// Password validator: sign-up needs at least 6 characters (Supabase's
/// default minimum).
String? validatePassword(String? value, {required bool isRegister}) {
  final v = value ?? '';
  if (v.isEmpty) return 'Enter your password';
  if (isRegister && v.length < 6) return 'Use at least 6 characters';
  return null;
}

class _Welcome extends StatelessWidget {
  final bool isRegister;

  const _Welcome({required this.isRegister});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return Column(
      children: [
        TweenAnimationBuilder<double>(
          tween: Tween(begin: reduce ? 1 : 0.6, end: 1),
          duration: reduce ? Duration.zero : const Duration(milliseconds: 700),
          curve: Curves.elasticOut,
          builder: (context, scale, child) =>
              Transform.scale(scale: scale, child: child),
          child: const MascotAvatar(title: 'Sprout', size: 104),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(AppTheme.radius),
            border: Border.all(
              color: AppColors.sunshine.withValues(alpha: 0.7),
              width: 2,
            ),
          ),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: Text(
              isRegister
                  ? 'A new hero! Let’s set up your adventure.'
                  : 'Welcome back, adventurer! Ready for today’s quest?',
              key: ValueKey(isRegister),
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium,
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Habit Quest',
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w800,
            color: theme.colorScheme.primary,
          ),
        ),
      ],
    );
  }
}

class _Banner extends StatelessWidget {
  final String emoji;
  final Color color;
  final String? title;
  final String message;

  const _Banner({
    super.key,
    required this.emoji,
    required this.color,
    this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(AppTheme.radius),
        border: Border.all(color: color.withValues(alpha: 0.6), width: 2),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 22)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title != null)
                  Text(
                    title!,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                Text(message, style: theme.textTheme.bodyMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
