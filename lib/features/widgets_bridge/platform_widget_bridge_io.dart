import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io' show Platform;
import 'dart:isolate';
import 'dart:ui' show IsolateNameServer;

import 'package:home_widget/home_widget.dart';

import '../auth/session_store.dart';
import 'home_widget_store.dart';
import 'widget_background_refresh.dart';
import 'widget_constants.dart';
import 'widget_store.dart';
import 'widget_links.dart';
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

/// Listens for the background isolates' signals while the app runs (same
/// process): the check-off callback's "apply the queue" ([onSignal]) and
/// the background refresh's "you are alive, refresh yourself"
/// ([onRefresh], acknowledged on the given SendPort). Returns a disposer.
void Function() listenForWidgetSignals(
  void Function() onSignal, {
  void Function()? onRefresh,
}) {
  if (!_supported) return () {};
  final port = ReceivePort();
  IsolateNameServer.removePortNameMapping(WidgetConstants.appPortName);
  IsolateNameServer.registerPortWithName(
    port.sendPort,
    WidgetConstants.appPortName,
  );
  final sub = port.listen((message) {
    if (message is List &&
        message.length == 2 &&
        message[0] == WidgetConstants.refreshSignal) {
      final reply = message[1];
      if (onRefresh == null) {
        if (reply is SendPort) reply.send(false);
        return;
      }
      if (reply is SendPort) reply.send(true);
      onRefresh();
      return;
    }
    onSignal();
  });
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
///
/// It also runs the daily refresh: Android's `WidgetRefreshWorker`
/// (WorkManager, see docs/WIDGETS.md) sends `habitquest://widget/refresh`
/// through the same receiver after midnight and every few hours.
@pragma('vm:entry-point')
Future<void> widgetInteractivityCallback(Uri? uri) async {
  if (isWidgetRefreshUri(uri)) {
    await _runBackgroundRefresh(uri!);
    return;
  }
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


/// The daily refresh in the headless isolate. When the app is alive (same
/// process) it does the refresh itself: its isolate owns the session and
/// the hive boxes. The outcome is reported to the native worker under
/// [WidgetConstants.refreshStatusKey]. Never throws.
Future<void> _runBackgroundRefresh(Uri uri) async {
  const store = HomeWidgetStore();
  var outcome = WidgetRefreshOutcome.retryLater.name;
  try {
    if (await _askRunningAppToRefresh()) {
      outcome = 'delegated';
    } else {
      outcome = (await refreshWidgetSnapshotInBackground(
        store: store,
        // A failing keystore read must not wipe the session.
        sessions: SecureSessionStore(null, false),
        now: DateTime.now(),
      ))
          .name;
    }
  } on Object catch (e) {
    developer.log('Background widget refresh failed: $e',
        name: 'WidgetBridge');
  }
  developer.log('Background widget refresh: $outcome', name: 'WidgetBridge');
  final id = uri.queryParameters[WidgetConstants.refreshIdParam];
  if (id == null) return;
  try {
    await store.write(
      WidgetConstants.refreshStatusKey,
      jsonEncode({'id': id, 'outcome': outcome}),
    );
  } on Object catch (_) {
    // The worker times out and treats it as done.
  }
}

/// Asks the running app (if any) to refresh; `true` if it acknowledged.
/// A port left behind by a dead isolate simply times out.
Future<bool> _askRunningAppToRefresh() async {
  final app = IsolateNameServer.lookupPortByName(WidgetConstants.appPortName);
  if (app == null) return false;
  final reply = ReceivePort();
  try {
    app.send([WidgetConstants.refreshSignal, reply.sendPort]);
    final answer = await reply.first.timeout(
      const Duration(seconds: 3),
      onTimeout: () => false,
    );
    return answer == true;
  } finally {
    reply.close();
  }
}
