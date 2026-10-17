import 'dart:developer' as developer;
import 'dart:io' show Platform;
import 'dart:isolate';
import 'dart:ui' show IsolateNameServer;

import 'package:home_widget/home_widget.dart';

import 'home_widget_store.dart';
import 'widget_constants.dart';
import 'widget_store.dart';
import 'widget_toggle_queue.dart';

bool get _supported => Platform.isAndroid || Platform.isIOS;

/// The home_widget store on Android / iOS; `null` elsewhere (desktop).
WidgetStore? createPlatformWidgetStore() =>
    _supported ? const HomeWidgetStore() : null;

/// Sets the iOS App Group and registers [widgetInteractivityCallback] (the
/// handles are saved natively, so it also works when the app is not
/// running). Failures are logged, never thrown.
Future<void> initPlatformWidgets() async {
  if (!_supported) return;
  try {
    await HomeWidget.setAppGroupId(WidgetConstants.appGroupId);
    await HomeWidget.registerInteractivityCallback(
      widgetInteractivityCallback,
    );
  } on Object catch (e) {
    developer.log('Widget setup failed: $e', name: 'WidgetBridge');
  }
}

/// Listens for the background callback's "apply the queue" signal while
/// the app runs (same process, other isolate). Returns a disposer.
void Function() listenForWidgetSignals(void Function() onSignal) {
  if (!_supported) return () {};
  final port = ReceivePort();
  IsolateNameServer.removePortNameMapping(WidgetConstants.appPortName);
  IsolateNameServer.registerPortWithName(
    port.sendPort,
    WidgetConstants.appPortName,
  );
  final sub = port.listen((_) => onSignal());
  return () {
    sub.cancel();
    port.close();
    IsolateNameServer.removePortNameMapping(WidgetConstants.appPortName);
  };
}

/// home_widget's interactive background callback (Android broadcast /
/// iOS 17 AppIntent → `habitquest://widget/toggle?habitId=`). Runs in a
/// headless isolate: it only queues the check-off and updates the snapshot
/// (see `widget_toggle_queue.dart`), then pokes the app if it is running.
@pragma('vm:entry-point')
Future<void> widgetInteractivityCallback(Uri? uri) async {
  try {
    await HomeWidget.setAppGroupId(WidgetConstants.appGroupId);
    final toggle = await handleWidgetInteraction(
      uri,
      const HomeWidgetStore(),
      now: DateTime.now(),
    );
    if (toggle != null) {
      IsolateNameServer.lookupPortByName(
        WidgetConstants.appPortName,
      )?.send('apply');
    }
  } on Object catch (e) {
    developer.log('Widget check-off failed: $e', name: 'WidgetBridge');
  }
}
