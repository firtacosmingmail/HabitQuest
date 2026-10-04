import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'notifications_providers.dart';

/// Starts reminder syncing once the app is up and resyncs on resume (which
/// also tops up every-N-days one-shot reminders). Wraps the app in
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
    controller.start();
    _lifecycle = AppLifecycleListener(onResume: controller.resync);
  }

  @override
  void dispose() {
    _lifecycle?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
