import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_providers.dart';
import 'sync_providers.dart';

/// Starts automatic sync once the app is up: forwards auth changes (app
/// start when signed in, login, logout) and app resumes to the
/// [SyncController]. Wraps the app in `main.dart`; widget tests that pump
/// `HabitQuestApp` directly skip it, so they never touch the network.
class SyncBootstrap extends ConsumerStatefulWidget {
  final Widget child;

  const SyncBootstrap({super.key, required this.child});

  @override
  ConsumerState<SyncBootstrap> createState() => _SyncBootstrapState();
}

class _SyncBootstrapState extends ConsumerState<SyncBootstrap> {
  AppLifecycleListener? _lifecycle;

  @override
  void initState() {
    super.initState();
    final controller = ref.read(syncControllerProvider.notifier);
    controller.start();
    ref.listenManual<AuthState>(
      authControllerProvider,
      (previous, next) {
        final before = previous is SignedIn ? previous.session.user.id : null;
        final after = next is SignedIn ? next.session.user.id : null;
        if (before != after || next is SignedOut) {
          controller.onAuthChanged(next);
        }
      },
    );
    _lifecycle = AppLifecycleListener(onResume: controller.onAppResumed);
  }

  @override
  void dispose() {
    _lifecycle?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
