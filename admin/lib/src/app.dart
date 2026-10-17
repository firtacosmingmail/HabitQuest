import 'package:flutter/material.dart';

import 'api/admin_api.dart';
import 'api/api_exception.dart';
import 'ui/charts.dart';
import 'ui/quotes_screen.dart';
import 'ui/schedule_screen.dart';
import 'ui/sign_in_screen.dart';
import 'ui/stats_screen.dart';

enum _Phase { signedOut, notAuthorised, admin }

/// The admin console. Only admins get past sign-in: after `auth-login` the
/// console asks the server (`GET /admin-stats/me`); a 403 shows
/// "Not authorised". The server checks the admin again on every call.
class AdminApp extends StatelessWidget {
  final AdminApi api;
  final DateTime Function() now;
  final String? banner;

  const AdminApp({
    super.key,
    required this.api,
    this.now = DateTime.now,
    this.banner,
  });

  @override
  Widget build(BuildContext context) {
    ThemeData theme(Brightness b) => ThemeData(
      colorSchemeSeed: const Color(0xFF2A78D6),
      brightness: b,
      extensions: [b == Brightness.dark ? VizTokens.dark : VizTokens.light],
    );
    return MaterialApp(
      title: 'HabitQuest Admin',
      debugShowCheckedModeBanner: false,
      theme: theme(Brightness.light),
      darkTheme: theme(Brightness.dark),
      home: AdminGate(api: api, now: now, banner: banner),
    );
  }
}

class AdminGate extends StatefulWidget {
  final AdminApi api;
  final DateTime Function() now;
  final String? banner;

  const AdminGate({
    super.key,
    required this.api,
    required this.now,
    this.banner,
  });

  @override
  State<AdminGate> createState() => _AdminGateState();
}

class _AdminGateState extends State<AdminGate> {
  _Phase _phase = _Phase.signedOut;
  String? _email;

  /// Returns an error message, or null on success (admin or not).
  Future<String?> _signIn(String email, String password) async {
    try {
      final session = await widget.api.signIn(email, password);
      _email = session.email ?? email;
    } on ApiException catch (e) {
      return switch (e.code) {
        ApiException.invalidCredentials => 'Wrong email or password.',
        'email_not_confirmed' => 'Confirm your email address first.',
        ApiException.networkError => 'Could not reach the server.',
        _ => e.message,
      };
    }
    try {
      await widget.api.checkAdmin();
      setState(() => _phase = _Phase.admin);
    } on ApiException catch (e) {
      if (e.status == 403 || e.isForbidden) {
        setState(() => _phase = _Phase.notAuthorised);
        return null;
      }
      await widget.api.signOut();
      return e.message;
    }
    return null;
  }

  Future<void> _signOut() async {
    await widget.api.signOut();
    setState(() {
      _phase = _Phase.signedOut;
      _email = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    switch (_phase) {
      case _Phase.signedOut:
        return SignInScreen(onSignIn: _signIn, banner: widget.banner);
      case _Phase.notAuthorised:
        return NotAuthorisedScreen(email: _email, onSignOut: _signOut);
      case _Phase.admin:
        return AdminShell(
          api: widget.api,
          now: widget.now,
          email: _email,
          onSignOut: _signOut,
        );
    }
  }
}

class NotAuthorisedScreen extends StatelessWidget {
  final String? email;
  final VoidCallback onSignOut;

  const NotAuthorisedScreen({super.key, this.email, required this.onSignOut});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock_outline, size: 48),
              const SizedBox(height: 16),
              Text('Not authorised', style: text.headlineSmall),
              const SizedBox(height: 8),
              Text(
                '${email ?? 'This account'} is not a HabitQuest admin. '
                'Ask an admin to add your email to QUOTE_ADMINS.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              OutlinedButton(
                onPressed: onSignOut,
                child: const Text('Sign out'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Navigation between the console's screens.
class AdminShell extends StatefulWidget {
  final AdminApi api;
  final DateTime Function() now;
  final String? email;
  final VoidCallback onSignOut;

  const AdminShell({
    super.key,
    required this.api,
    required this.now,
    this.email,
    required this.onSignOut,
  });

  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final screens = [
      QuotesScreen(api: widget.api, now: widget.now),
      ScheduleScreen(api: widget.api, now: widget.now),
      StatsScreen(api: widget.api, now: widget.now),
    ];
    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: _index,
            onDestinationSelected: (i) => setState(() => _index = i),
            labelType: NavigationRailLabelType.all,
            leading: const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'HQ Admin',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            trailing: Expanded(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (widget.email != null)
                        SizedBox(
                          width: 88,
                          child: Text(
                            widget.email!,
                            textAlign: TextAlign.center,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        ),
                      IconButton(
                        key: const ValueKey('sign-out'),
                        tooltip: 'Sign out',
                        onPressed: widget.onSignOut,
                        icon: const Icon(Icons.logout),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            destinations: const [
              NavigationRailDestination(
                icon: Icon(Icons.format_quote),
                label: Text('Quotes'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.calendar_month),
                label: Text('Schedule'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.insights),
                label: Text('Stats'),
              ),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(child: screens[_index]),
        ],
      ),
    );
  }
}
