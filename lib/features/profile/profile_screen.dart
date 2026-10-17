import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/router/app_routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../data/remote/account_api.dart';
import '../../data/remote/api_exception.dart';
import '../auth/auth_providers.dart';
import 'profile_controller.dart';

/// Profile (`/profile`, from the avatar in the Quest header): avatar
/// initials, editable display name, email, member since, sign-in method,
/// Change password (accounts with a password only), Logout and a danger
/// zone with Delete account.
class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  bool _deleting = false;

  void _snack(String text) {
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _changePassword() async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => const ChangePasswordDialog(),
    );
    if (changed == true && mounted) _snack('Password changed! 🔐');
  }

  Future<void> _deleteAccount() async {
    final deleted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const DeleteAccountDialog(),
    );
    if (deleted != true || !mounted) return;
    setState(() => _deleting = true);
    await ref.read(profileControllerProvider.notifier).finishAccountDeletion();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final profile = ref.watch(profileControllerProvider);
    final auth = ref.watch(authControllerProvider);
    final sessionEmail = auth is SignedIn ? auth.session.user.email : '';
    final data = profile.value;

    return Scaffold(
      appBar: AppBar(title: const Text('Your profile')),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            children: [
              _HeaderCard(
                profile: data,
                fallbackEmail: sessionEmail,
                loading: profile.isLoading && data == null,
              ),
              if (profile.hasError && data == null) ...[
                const SizedBox(height: 12),
                _LoadError(
                  error: profile.error,
                  onRetry: () =>
                      ref.read(profileControllerProvider.notifier).reload(),
                ),
              ],
              if (data != null) ...[
                const SizedBox(height: 16),
                _DetailsCard(profile: data),
              ],
              const SizedBox(height: 16),
              _SectionTitle('Account'),
              Card(
                margin: EdgeInsets.zero,
                child: Column(
                  children: [
                    if (data != null && data.hasPassword)
                      ListTile(
                        key: const ValueKey('change-password-button'),
                        leading: const Text(
                          '🔑',
                          style: TextStyle(fontSize: 24),
                        ),
                        title: const Text('Change password'),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: _changePassword,
                      ),
                    ListTile(
                      key: const ValueKey('logout-button'),
                      leading: const Text('👋', style: TextStyle(fontSize: 24)),
                      title: const Text('Log out'),
                      subtitle: const Text('Your habits stay on this device'),
                      onTap: () => confirmAndLogout(context, ref),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _SectionTitle('Inspiration'),
              Card(
                margin: EdgeInsets.zero,
                child: ListTile(
                  key: const ValueKey('profile-saved-quotes'),
                  leading: const Text('💖', style: TextStyle(fontSize: 24)),
                  title: const Text('Saved quotes'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => context.push(AppRoutes.savedQuotes),
                ),
              ),
              const SizedBox(height: 28),
              _DangerZone(onDelete: _deleteAccount),
              const SizedBox(height: 12),
              Text(
                'Signed in as ${data?.email ?? sessionEmail}',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          if (_deleting)
            const ColoredBox(
              color: Color(0x66000000),
              child: Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }
}

/// Asks for confirmation, then logs out (the auth gate then shows /login).
/// Local habit data stays on the device.
Future<void> confirmAndLogout(BuildContext context, WidgetRef ref) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      key: const ValueKey('logout-dialog'),
      icon: const Text('👋', style: TextStyle(fontSize: 40)),
      title: const Text('Leaving the quest?'),
      content: const Text(
        'You will be logged out. Your habits stay on this device.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Stay'),
        ),
        FilledButton(
          key: const ValueKey('confirm-logout'),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Log out'),
        ),
      ],
    ),
  );
  if (confirmed != true) return;
  await ref.read(authControllerProvider.notifier).logout();
}

/// Round avatar with the user's initials on a playful gradient.
class ProfileAvatar extends StatelessWidget {
  final String initials;
  final double size;

  const ProfileAvatar({super.key, required this.initials, this.size = 88});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          colors: [AppColors.grape, AppColors.coral],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: AppColors.sunshine, width: size / 22),
      ),
      child: Text(
        initials,
        style: Theme.of(context).textTheme.headlineMedium?.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: size * 0.36,
        ),
      ),
    );
  }
}

class _HeaderCard extends ConsumerStatefulWidget {
  final AccountProfile? profile;
  final String fallbackEmail;
  final bool loading;

  const _HeaderCard({
    required this.profile,
    required this.fallbackEmail,
    required this.loading,
  });

  @override
  ConsumerState<_HeaderCard> createState() => _HeaderCardState();
}

class _HeaderCardState extends ConsumerState<_HeaderCard> {
  final _name = TextEditingController();
  bool _editing = false;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _startEditing() {
    _name.text = widget.profile?.displayName ?? '';
    setState(() {
      _editing = true;
      _error = null;
    });
  }

  static String? validateName(String value) {
    final v = value.trim();
    if (v.isEmpty) return 'Give your hero a name';
    if (v.runes.length > 50) return 'Keep it to 50 characters';
    return null;
  }

  Future<void> _save() async {
    final error = validateName(_name.text);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(profileControllerProvider.notifier).rename(_name.text);
      if (!mounted) return;
      setState(() {
        _editing = false;
        _saving = false;
      });
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(const SnackBar(content: Text('Name updated! ✨')));
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e.isNetwork
            ? "You're offline. Try again when you're back online."
            : e.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = widget.profile;
    final email = p?.email ?? widget.fallbackEmail;
    final name = p?.displayName;
    return Container(
      key: const ValueKey('profile-header'),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
        gradient: LinearGradient(
          colors: [
            theme.colorScheme.primary.withValues(alpha: 0.18),
            AppColors.sunshine.withValues(alpha: 0.22),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        children: [
          ProfileAvatar(
            key: const ValueKey('profile-avatar'),
            initials: initialsFor(name, email),
          ),
          const SizedBox(height: 12),
          if (widget.loading)
            const Padding(
              padding: EdgeInsets.all(8),
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 3),
              ),
            )
          else if (_editing)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    key: const ValueKey('display-name-field'),
                    controller: _name,
                    autofocus: true,
                    maxLength: 50,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _save(),
                    decoration: InputDecoration(
                      labelText: 'Display name',
                      errorText: _error,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                IconButton(
                  key: const ValueKey('save-display-name'),
                  tooltip: 'Save',
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check_rounded),
                ),
                IconButton(
                  key: const ValueKey('cancel-display-name'),
                  tooltip: 'Cancel',
                  onPressed: _saving
                      ? null
                      : () => setState(() => _editing = false),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            )
          else
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: Text(
                    name?.isNotEmpty == true ? name! : 'Nameless hero',
                    key: const ValueKey('display-name'),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (p != null)
                  IconButton(
                    key: const ValueKey('edit-display-name'),
                    tooltip: 'Edit name',
                    onPressed: _startEditing,
                    icon: const Icon(Icons.edit_rounded, size: 20),
                  ),
              ],
            ),
          Text(
            email,
            key: const ValueKey('profile-email'),
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailsCard extends StatelessWidget {
  final AccountProfile profile;

  const _DetailsCard({required this.profile});

  @override
  Widget build(BuildContext context) {
    final since = profile.createdAt;
    return Row(
      children: [
        Expanded(
          child: _InfoTile(
            key: const ValueKey('member-since'),
            emoji: '🗓️',
            label: 'Member since',
            value: since == null
                ? '—'
                : DateFormat.yMMMM().format(since.toLocal()),
            accent: AppColors.sky,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _InfoTile(
            key: const ValueKey('sign-in-method'),
            emoji: signInMethodEmoji(profile.providers),
            label: 'Sign-in method',
            value: signInMethodLabel(profile.providers),
            accent: AppColors.mint,
          ),
        ),
      ],
    );
  }
}

class _InfoTile extends StatelessWidget {
  final String emoji;
  final String label;
  final String value;
  final Color accent;

  const _InfoTile({
    super.key,
    required this.emoji,
    required this.label,
    required this.value,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        border: Border.all(color: accent.withValues(alpha: 0.5), width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 24)),
          const SizedBox(height: 6),
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          Text(
            value,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _LoadError extends StatelessWidget {
  final Object? error;
  final VoidCallback onRetry;

  const _LoadError({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final offline = error is ApiException && (error as ApiException).isNetwork;
    return Card(
      key: const ValueKey('profile-load-error'),
      margin: EdgeInsets.zero,
      child: ListTile(
        leading: Text(
          offline ? '📡' : '🙈',
          style: const TextStyle(fontSize: 26),
        ),
        title: Text(offline ? "You're offline" : "Couldn't load your profile"),
        subtitle: const Text(
          'Your details show up once we can reach the server.',
        ),
        trailing: TextButton(onPressed: onRetry, child: const Text('Retry')),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;

  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
    child: Text(text, style: Theme.of(context).textTheme.titleLarge),
  );
}

class _DangerZone extends StatelessWidget {
  final VoidCallback onDelete;

  const _DangerZone({required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final danger = theme.colorScheme.error;
    return Container(
      key: const ValueKey('danger-zone'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: danger.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(AppTheme.radius),
        border: Border.all(color: danger.withValues(alpha: 0.6), width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '⚠️ Danger zone',
            style: theme.textTheme.titleMedium?.copyWith(color: danger),
          ),
          const SizedBox(height: 6),
          const Text(
            'Deleting your account removes your habits, check-ins, XP and '
            'achievements for good, on every device.',
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            key: const ValueKey('delete-account-button'),
            style: OutlinedButton.styleFrom(
              foregroundColor: danger,
              side: BorderSide(color: danger, width: 1.5),
            ),
            onPressed: onDelete,
            icon: const Icon(Icons.delete_forever_rounded),
            label: const Text('Delete account'),
          ),
        ],
      ),
    );
  }
}

/// Current / new / confirm password form. Pops `true` once changed.
class ChangePasswordDialog extends ConsumerStatefulWidget {
  const ChangePasswordDialog({super.key});

  @override
  ConsumerState<ChangePasswordDialog> createState() =>
      _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends ConsumerState<ChangePasswordDialog> {
  final _form = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _new = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  bool _obscure = true;
  String? _currentError;
  String? _newError;
  String? _error;

  @override
  void dispose() {
    _current.dispose();
    _new.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _currentError = null;
      _newError = null;
      _error = null;
    });
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(profileControllerProvider.notifier)
          .changePassword(
            currentPassword: _current.text,
            newPassword: _new.text,
          );
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        switch (e.code) {
          case ApiException.invalidCredentials:
            _currentError = "That's not your current password";
          case ApiException.weakPassword:
            _newError = 'That password is too easy to guess';
          case ApiException.samePassword:
            _newError = 'Pick something different from your current one';
          case ApiException.noPassword:
            _error = 'This account signs in without a password.';
          default:
            _error = e.isNetwork
                ? "You're offline. Try again when you're back online."
                : 'Something went wrong. Please try again.';
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    InputDecoration deco(String label, String? error) => InputDecoration(
      labelText: label,
      errorText: error,
      suffixIcon: IconButton(
        tooltip: _obscure ? 'Show passwords' : 'Hide passwords',
        icon: Icon(
          _obscure ? Icons.visibility_rounded : Icons.visibility_off_rounded,
        ),
        onPressed: () => setState(() => _obscure = !_obscure),
      ),
    );
    return AlertDialog(
      key: const ValueKey('change-password-dialog'),
      icon: const Text('🔑', style: TextStyle(fontSize: 40)),
      title: const Text('Change password'),
      content: SingleChildScrollView(
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                key: const ValueKey('current-password'),
                controller: _current,
                obscureText: _obscure,
                autofillHints: const [AutofillHints.password],
                decoration: deco('Current password', _currentError),
                validator: (v) =>
                    (v ?? '').isEmpty ? 'Enter your current password' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const ValueKey('new-password'),
                controller: _new,
                obscureText: _obscure,
                autofillHints: const [AutofillHints.newPassword],
                decoration: deco('New password', _newError),
                validator: (v) => validateNewPassword(v, _current.text),
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const ValueKey('confirm-password'),
                controller: _confirm,
                obscureText: _obscure,
                decoration: deco('Confirm new password', null),
                validator: (v) =>
                    v != _new.text ? "Passwords don't match" : null,
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  key: const ValueKey('change-password-error'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('submit-change-password'),
          onPressed: _busy ? null : _submit,
          child: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Change'),
        ),
      ],
    );
  }
}

/// New-password rules (the project's: 6–72 characters, not the current one).
String? validateNewPassword(String? value, String current) {
  final v = value ?? '';
  if (v.isEmpty) return 'Enter a new password';
  if (v.length < 6) return 'Use at least 6 characters';
  if (v.length > 72) return 'Keep it to 72 characters';
  if (v == current) return 'Pick something different from your current one';
  return null;
}

/// Explains what deletion removes; the user must type DELETE. Deletes the
/// account (server + local data) and pops `true`; the caller then signs out.
class DeleteAccountDialog extends ConsumerStatefulWidget {
  const DeleteAccountDialog({super.key});

  @override
  ConsumerState<DeleteAccountDialog> createState() =>
      _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends ConsumerState<DeleteAccountDialog> {
  final _confirm = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _confirm.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _confirm.dispose();
    super.dispose();
  }

  bool get _confirmed => _confirm.text.trim() == deleteConfirmationWord;

  Future<void> _delete() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(profileControllerProvider.notifier).deleteAccount();
      if (mounted) Navigator.of(context).pop(true);
    } on OfflineException {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = OfflineException.message;
        });
      }
    } on ApiException {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = "We couldn't delete your account. Please try again.";
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final danger = theme.colorScheme.error;
    Widget bullet(String emoji, String text) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(emoji),
          const SizedBox(width: 8),
          Expanded(child: Text(text)),
        ],
      ),
    );
    return AlertDialog(
      key: const ValueKey('delete-account-dialog'),
      icon: const Text('😢', style: TextStyle(fontSize: 40)),
      title: const Text('Delete your account?'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('This is permanent and cannot be undone. We will:'),
            const SizedBox(height: 8),
            bullet('🗑️', 'Delete your habits and check-ins'),
            bullet('🏆', 'Erase your XP, level and achievements'),
            bullet('📱', 'Remove all of it from this device too'),
            bullet('🔕', 'Cancel your reminders'),
            const SizedBox(height: 12),
            Text.rich(
              TextSpan(
                children: [
                  const TextSpan(text: 'Type '),
                  TextSpan(
                    text: deleteConfirmationWord,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: danger,
                    ),
                  ),
                  const TextSpan(text: ' to confirm.'),
                ],
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              key: const ValueKey('delete-confirm-field'),
              controller: _confirm,
              enabled: !_busy,
              autocorrect: false,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(hintText: 'DELETE'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                key: const ValueKey('delete-account-error'),
                style: TextStyle(color: danger, fontWeight: FontWeight.w700),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('cancel-delete-account'),
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: const Text('Keep my account'),
        ),
        FilledButton(
          key: const ValueKey('confirm-delete-account'),
          style: FilledButton.styleFrom(
            backgroundColor: danger,
            foregroundColor: theme.colorScheme.onError,
          ),
          onPressed: _confirmed && !_busy ? _delete : null,
          child: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Delete forever'),
        ),
      ],
    );
  }
}
