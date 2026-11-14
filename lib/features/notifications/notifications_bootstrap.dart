import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_providers.dart';
import '../projects/notifications/project_notifications_providers.dart';
import 'notifications_providers.dart';

/// Starts reminder syncing once the app is up and resyncs on resume (which
/// also tops up every-N-days one-shot reminders). Also runs the Projects
/// notifications: started after the habit reminders (same scheduler),
/// re-planned on resume (the rolling window) and on sign-in / sign-out. Wraps the app in
/// `main.dart`; tests that pump `HabitQuestApp` directly skip it.
class NotificationsBootstrap extends ConsumerStatefulWidget {
  final Widget child;

  const NotificationsBootstrap({super.key, required this.child});

  @override
  ConsumerState<NotificationsBootstrap> createState() =>
      _NotificationsBootstrapState();
}

class _NotificationsBootstrapState
    extends ConsumerState<NotificationsBootstrap> {
  AppLifecycleListener? _lifecycle;

  @override
  void initState() {
    super.initState();
    final controller = ref.read(notificationsControllerProvider);
    final projects = ref.read(projectNotificationsControllerProvider);
    // Sequential: the scheduler's one-time init runs in the first start.
    controller.start().then((_) => projects.start());
    _lifecycle = AppLifecycleListener(
      onResume: () {
        controller.resync();
        projects.resync();
      },
    );
    ref.listenManual<bool>(
      authControllerProvider.select((s) => s is SignedIn),
      (previous, next) {
        if (previous != null && previous != next) projects.resync();
      },
    );
  }

  @override
  void dispose() {
    _lifecycle?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
