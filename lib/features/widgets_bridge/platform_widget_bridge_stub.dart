import 'widget_store.dart';

/// Web: no home-screen widgets.
WidgetStore? createPlatformWidgetStore() => null;

/// Web: nothing to set up.
Future<void> initPlatformWidgets() async {}

/// Web: no background isolate to hear from. Returns a disposer.
void Function() listenForWidgetSignals(void Function() onSignal) => () {};
