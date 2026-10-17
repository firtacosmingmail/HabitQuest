import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'platform_widget_bridge.dart';
import 'widget_bridge.dart';

/// Starts the home-screen widget bridge once the app is up: App Group and
/// interactive callback setup, the snapshot writer, queued check-offs on
/// start / resume / background signal. Wraps the app in `main.dart`; widget
/// tests that pump `HabitQuestApp` directly skip it. No-op on web.
class WidgetBridgeBootstrap extends ConsumerStatefulWidget {
  final Widget child;

  const WidgetBridgeBootstrap({super.key, required this.child});

  @override
  ConsumerState<WidgetBridgeBootstrap> createState() =>
      _WidgetBridgeBootstrapState();
}

class _WidgetBridgeBootstrapState extends ConsumerState<WidgetBridgeBootstrap> {
  AppLifecycleListener? _lifecycle;
  void Function()? _stopSignals;

  @override
  void initState() {
    super.initState();
    if (kIsWeb) return;
    final bridge = ref.read(widgetBridgeProvider);
    if (bridge == null) return;
    unawaited(initPlatformWidgets().then((_) => bridge.start()));
    _stopSignals = listenForWidgetSignals(() => bridge.applyQueue());
    _lifecycle = AppLifecycleListener(onResume: bridge.onResume);
  }

  @override
  void dispose() {
    _lifecycle?.dispose();
    _stopSignals?.call();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
